package com.posey.camera

import android.content.Context
import android.graphics.BitmapFactory
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.URI
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class PoseyAiStore private constructor(context: Context) {
    val app: Context = context.applicationContext
    val directory = File(app.filesDir, "PoseyAIJobs").apply { mkdirs() }
    private val preferences = app.getSharedPreferences("posey.background-ai", Context.MODE_PRIVATE)
    private val lock = Any()
    val memoryResults = ConcurrentHashMap<String, ByteArray>()
    private val acceptedActivations=ConcurrentHashMap.newKeySet<String>()

    companion object {
        @Volatile private var instance: PoseyAiStore? = null
        fun get(context: Context): PoseyAiStore = instance ?: synchronized(this) {
            instance ?: PoseyAiStore(context).also { instance = it; it.recoverProcess() }
        }
        fun validId(id: String): Boolean = try { UUID.fromString(id).toString().equals(id, true) } catch (_: Exception) { false }
        fun https(value: String): Boolean = try { val uri = URI(value); uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null } catch (_: Exception) { false }
    }

    private fun read(): MutableList<JSONObject> {
        val data = JSONArray(preferences.getString("jobs", "[]"))
        require(data.length() <= 2000) { "后台任务记录过多，请先清理。" }
        val result = mutableListOf<JSONObject>()
        val ids = mutableSetOf<String>()
        for (index in 0 until data.length()) {
            val item = data.getJSONObject(index)
            require(validId(item.getString("id")) && ids.add(item.getString("id"))) { "后台任务记录无法读取。" }
            require(item.getString("state") in setOf("staged", "queued", "generating", "awaitingResult", "completed", "failed", "cancelled")) { "后台任务状态无效。" }
            result.add(item)
        }
        return result
    }
    private fun save(records: List<JSONObject>) {
        if (!preferences.edit().putString("jobs", JSONArray(records).toString()).commit()) throw IOException("后台任务记录未能保存。")
    }
    fun records(): List<JSONObject> = synchronized(lock) {
        val records = read()
        for (record in records) {
            val id = record.getString("id")
            if(record.getString("state")=="staged") {
                record.put("state",if(acceptedActivations.contains(id))"queued" else "failed")
                if(!acceptedActivations.contains(id))record.put("message","任务未能启动，没有发送生成请求。")
            }
            if (record.getString("state") !in setOf("cancelled", "completed") && resultFile(id).isFile) {
                record.put("state", "completed").put("completedAt", resultFile(id).lastModified()).remove("pendingResult")
            }
            if (memoryResults.containsKey(id) && record.getString("state") != "cancelled") {
                record.put("state", "awaitingResult").put("pendingResult", "save")
            }
        }
        records.sortedByDescending { it.optLong("createdAt") }
    }
    fun record(id: String): JSONObject? = records().firstOrNull { it.getString("id") == id }
    fun update(id: String, state: String, message: String? = null, pending: String? = null) = synchronized(lock) {
        val records = read()
        val record = records.firstOrNull { it.getString("id") == id } ?: return@synchronized
        if (record.getString("state") == "cancelled" && state != "cancelled") return@synchronized
        record.put("state", state)
        if (message == null) record.remove("message") else record.put("message", message)
        if (pending == null) record.remove("pendingResult") else record.put("pendingResult", pending)
        if (state == "completed") record.put("completedAt", System.currentTimeMillis())
        save(records)
    }
    fun safeUpdate(id: String, state: String, message: String? = null, pending: String? = null) {
        try { update(id, state, message, pending) } catch (_: Exception) { /* Durable result files remain recoverable. */ }
    }
    fun prepare(id: String, arguments: Map<*, *>) = synchronized(lock) {
        require(validId(id)) { "任务编号无效。" }
        val records = read()
        require(records.none { it.getString("id") == id }) { "任务已提交。" }
        require(records.count { it.getString("state") in setOf("queued", "generating") } < 3) { "最多保留 3 个进行中的任务。" }
        require(records.none { it.getString("state") == "awaitingResult" }) { "请先保存未留存的成片。" }
        val endpoint = arguments["endpoint"] as? String ?: ""
        val key = arguments["apiKey"] as? String ?: ""
        val model = arguments["model"] as? String ?: ""
        val prompt = arguments["prompt"] as? String ?: ""
        val source = arguments["sourceImage"] as? String ?: ""
        val guide = arguments["guideImage"] as? String ?: ""
        require(https(endpoint) && key.isNotBlank() && model.isNotBlank() && prompt.isNotBlank()) { "生成配置不完整。" }
        require(source.length <= 16 * 1024 * 1024 && guide.length <= 16 * 1024 * 1024) { "照片过大。" }
        val sourceBytes = Base64.decode(source.substringAfter(','), Base64.DEFAULT)
        require(validImage(sourceBytes)) { "照片格式无效。" }
        try {
            atomic(sourceFile(id), sourceBytes)
            secret(id, JSONObject().put("apiKey", key))
            val body = JSONObject().put("model", model).put("prompt", prompt).put("image", JSONArray(listOf(source, guide)))
                .put("size", "2K").put("output_format", "jpeg").put("response_format", "b64_json").put("watermark", false)
            atomic(requestFile(id), body.toString().toByteArray(Charsets.UTF_8))
            val metadata = arguments["metadata"] as? Map<*, *> ?: emptyMap<Any, Any>()
            val safeMetadata = JSONObject()
            for (name in listOf("targetId", "targetSnapshot", "requestMetadata", "sourceWorkId", "retryOf")) {
                if (metadata[name] != null) safeMetadata.put(name, JSONObject.wrap(metadata[name]))
            }
            records.add(JSONObject().put("id", id).put("state", "staged").put("createdAt", System.currentTimeMillis())
                .put("targetTitle", arguments["targetTitle"] as? String ?: "目标姿势").put("endpoint", endpoint).put("metadata", safeMetadata))
            save(records)
        } catch (failure: Exception) { removeFiles(id); throw failure }
    }
    fun accepted(id:String)=synchronized(lock){if(read().any{it.getString("id")==id&&it.getString("state")=="staged"})acceptedActivations.add(id)}
    fun activate(id:String)=synchronized(lock){
        val records=read();val job=records.firstOrNull{it.getString("id")==id}?:return@synchronized
        acceptedActivations.remove(id)
        if(job.getString("state")!="staged")return@synchronized
        if(records.count{it.getString("state") in setOf("queued","generating")}>=3){job.put("state","failed").put("message","后台队列已满，任务未发送。")}
        else{job.put("state","queued")}
        save(records)
    }
    fun cancel(id: String) { require(validId(id)); update(id, "cancelled"); memoryResults.remove(id);requestFile(id).delete();secretFile(id).delete() }
    fun clear(id: String) = synchronized(lock) {
        require(validId(id))
        val records = read().filterNot { it.getString("id") == id }
        save(records)
        removeFiles(id)
    }
    fun prune() = synchronized(lock) {
        val records = read()
        val removed = records.filter { it.getString("state") == "completed" }.sortedByDescending { it.optLong("createdAt") }.drop(20)
        if (removed.isEmpty()) return@synchronized
        save(records.filterNot { item -> removed.any { it.getString("id") == item.getString("id") } })
        removed.forEach { removeFiles(it.getString("id")) }
    }
    fun next(): JSONObject? = records().filter { it.getString("state") == "queued" }.minByOrNull { it.optLong("createdAt") }
    fun pending(): Boolean = records().any { it.getString("state") == "awaitingResult" }
    fun active(): Int = records().count { it.getString("state") in setOf("queued", "generating") }
    private fun recoverProcess() = synchronized(lock) {
        try {
            val records = read()
            for (record in records) {
                if (record.getString("state") == "generating") {
                    val id = record.getString("id")
                    if (resultFile(id).isFile) record.put("state", "completed").put("completedAt", resultFile(id).lastModified())
                    else record.put("state", "failed").put("message", "上次任务已中断，服务可能已处理，请核对后再决定是否重试。")
                    requestFile(id).delete(); secretFile(id).delete()
                }
            }
            save(records)
        } catch (_: Exception) { /* Explicit repair retains the unreadable original. */ }
    }
    fun repair(): Boolean = synchronized(lock) {
        try { read(); false } catch (_: Exception) {
            val original = preferences.getString("jobs", "[]") ?: "[]"
            atomic(File(directory, "recovery-${UUID.randomUUID()}.json"), original.toByteArray(Charsets.UTF_8))
            save(emptyList()); true
        }
    }
    fun requestFile(id: String) = File(directory, "$id-request.json")
    fun sourceFile(id: String) = File(directory, "$id-source.jpg")
    fun resultFile(id: String) = File(directory, "$id-result.jpg")
    fun secretFile(id: String) = File(directory, "$id-secret.enc")
    fun image(id: String, source: Boolean): ByteArray? {
        require(validId(id))
        if (record(id) == null) return null
        if (!source) memoryResults[id]?.let { return it }
        val file = if (source) sourceFile(id) else resultFile(id)
        return if (file.isFile && file.length() <= 24 * 1024 * 1024) file.readBytes() else null
    }
    fun acceptResult(id: String, bytes: ByteArray): Boolean {
        require(validImage(bytes)) { "服务返回的图片格式无效。" }
        if (record(id)?.getString("state") == "cancelled" || record(id) == null) return false
        memoryResults[id] = bytes
        return try {
            atomic(resultFile(id), bytes)
            if (record(id)?.getString("state") == "cancelled" || record(id) == null) { resultFile(id).delete(); memoryResults.remove(id); false }
            else { memoryResults.remove(id); safeUpdate(id, "completed"); secretFile(id).delete(); prune(); true }
        } catch (_: Exception) { safeUpdate(id, "awaitingResult", "成片已生成，图片未能写入。释放空间后可重试保存。", "save"); false }
    }
    private fun removeFiles(id: String) { memoryResults.remove(id); listOf(requestFile(id), sourceFile(id), resultFile(id), secretFile(id)).forEach { it.delete() } }
    fun atomic(file: File, bytes: ByteArray) {
        val atomic = AtomicFile(file); val output = atomic.startWrite()
        try { output.write(bytes); atomic.finishWrite(output) } catch (failure: Exception) { atomic.failWrite(output); throw failure }
    }
    fun validImage(bytes: ByteArray): Boolean {
        if (bytes.size > 24 * 1024 * 1024) return false
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        return options.outWidth > 0 && options.outHeight > 0 && options.outWidth.toLong() * options.outHeight <= 16 * 1024 * 1024
    }
    private fun key(): SecretKey = synchronized(lock) {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("posey.ai.credentials.v1", null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder("posey.ai.credentials.v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build()); generateKey()
        }
    }
    fun secret(id: String, data: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
        val value = JSONObject().put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("data", Base64.encodeToString(cipher.doFinal(data.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
        atomic(secretFile(id), value.toString().toByteArray(Charsets.UTF_8))
    }
    fun secret(id: String): JSONObject {
        val value = JSONObject(secretFile(id).readText()); val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(value.getString("iv"), Base64.DEFAULT)))
        return JSONObject(String(cipher.doFinal(Base64.decode(value.getString("data"), Base64.DEFAULT)), Charsets.UTF_8))
    }
}
