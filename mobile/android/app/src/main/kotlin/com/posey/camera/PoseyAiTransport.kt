package com.posey.camera

import android.util.Base64
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

internal class PoseyAiTransport(private val store: PoseyAiStore) {
    private val connections = ConcurrentHashMap<String, HttpURLConnection>()
    companion object {
        @Volatile private var instance: PoseyAiTransport? = null
        fun get(store: PoseyAiStore): PoseyAiTransport = instance ?: synchronized(this) { instance ?: PoseyAiTransport(store).also { instance = it } }
    }
    fun disconnect(id: String) { connections.remove(id)?.disconnect() }
    fun disconnectAll() { connections.keys.toList().forEach(::disconnect) }
    fun run(id: String) {
        try {
            if (store.record(id)?.optString("state") != "queued") return
            store.update(id, "generating")
            val record = store.record(id) ?: return
            val credentials = store.secret(id)
            val endpoint = record.getString("endpoint")
            require(PoseyAiStore.https(endpoint))
            val body = store.requestFile(id).readBytes()
            val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false; connectTimeout = 30_000; readTimeout = 300_000
                requestMethod = "POST"; doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer ${credentials.getString("apiKey")}")
                setFixedLengthStreamingMode(body.size)
            }
            connections[id] = connection
            try {
                if (store.record(id)?.optString("state") == "cancelled") return
                connection.outputStream.use { it.write(body) }
                val status = connection.responseCode
                if (status !in 200..299) throw PublicFailure(publicStatus(status))
                val payload = JSONObject(String(read(connection, 32 * 1024 * 1024), Charsets.UTF_8))
                val item = payload.optJSONArray("data")?.optJSONObject(0) ?: throw PublicFailure("服务没有返回可用图片。")
                if (store.record(id)?.optString("state") == "cancelled" || store.record(id) == null) return
                val encoded = item.optString("b64_json", "")
                if (encoded.isNotEmpty()) store.acceptResult(id, Base64.decode(encoded, Base64.DEFAULT))
                else {
                    val resultUrl = item.optString("url", "")
                    if (!PoseyAiStore.https(resultUrl)) throw PublicFailure("服务返回的图片地址无效。")
                    store.secret(id, JSONObject().put("resultUrl", resultUrl))
                    try { store.acceptResult(id, download(id, resultUrl)) }
                    catch (_: Exception) { store.safeUpdate(id, "awaitingResult", "成片下载中断，可以重试下载，无需再次生成。", "download") }
                }
            } finally { connections.remove(id); connection.disconnect() }
        } catch (failure: Exception) {
            val state = store.record(id)?.optString("state")
            if (state != null && state != "cancelled" && state != "completed" && state != "awaitingResult") {
                store.safeUpdate(id, "failed", if (failure is PublicFailure) failure.message else "任务已中断，服务可能已处理。请核对后再决定是否重试。")
            }
        } finally {
            store.requestFile(id).delete()
            val row = store.record(id)
            if (row?.optString("pendingResult") != "download") store.secretFile(id).delete()
        }
    }
    fun retryResult(id: String) {
        val record = store.record(id) ?: throw PublicFailure("任务记录已移除。")
        if (record.optString("state") == "completed") return
        require(record.optString("state") == "awaitingResult") { "任务没有待保存成片。" }
        val bytes = store.memoryResults[id] ?: if (store.resultFile(id).isFile) store.resultFile(id).readBytes()
            else download(id, store.secret(id).getString("resultUrl"))
        if (!store.acceptResult(id, bytes)) throw PublicFailure("图片仍未保存，请释放存储空间后重试。")
    }
    private fun download(id: String, value: String): ByteArray {
        if (!PoseyAiStore.https(value)) throw PublicFailure("成片地址无效。")
        val connection = (URL(value).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = false; connectTimeout = 20_000; readTimeout = 45_000
        }
        connections[id] = connection
        try {
            if (connection.responseCode != 200) throw PublicFailure("成片暂时无法下载。地址可能已失效，请先查看服务记录。")
            return read(connection, 24 * 1024 * 1024)
        } finally { connections.remove(id); connection.disconnect() }
    }
    private fun read(connection: HttpURLConnection, limit: Int): ByteArray {
        if (connection.contentLengthLong > limit) throw PublicFailure("服务返回的图片过大。")
        val result = ByteArrayOutputStream()
        connection.inputStream.use { input ->
            val buffer = ByteArray(64 * 1024); var total = 0
            while (true) { val count = input.read(buffer); if (count < 0) break; total += count
                if (total > limit) throw PublicFailure("服务返回的数据过大。")
                result.write(buffer, 0, count)
            }
        }
        return result.toByteArray()
    }
    private fun publicStatus(status: Int): String = when (status) {
        401, 403 -> "服务鉴权失败，请检查密钥与模型权限。"
        429 -> "服务请求过多，请稍后再试。"
        400 -> "生成参数未被服务接受，请核对图像模型和服务地址。"
        in 300..399 -> "服务地址发生重定向，请填写最终 HTTPS 地址。"
        else -> "服务暂时无法生成，请稍后再试。"
    }
    private class PublicFailure(message: String) : Exception(message)
}
