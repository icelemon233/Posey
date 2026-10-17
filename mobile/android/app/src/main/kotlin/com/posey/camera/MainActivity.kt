package com.posey.camera

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var platform: MethodChannel? = null
    @Volatile private var documentResult: MethodChannel.Result? = null
    private var exportSource: File? = null
    private var notificationResult: MethodChannel.Result? = null
    @Volatile private var foreground = false
    private var pendingJob: String? = null
    private val limit = 1024L * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingJob = intent?.getStringExtra("poseyJobId")?.takeIf(PoseyAiStore::validId)
        platform = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.posey.camera/platform").also { channel ->
            channel.setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                when (call.method) {
                    "openSettings" -> attempt(result) {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "requestNotifications" -> requestNotifications(args["force"] == true, result)
                    "pendingJob" -> { result.success(pendingJob); pendingJob = null }
                    "appInfo" -> attempt(result) {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION") val build = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success(mapOf("name" to "Posey", "version" to info.versionName, "build" to build, "developer" to "Cinna"))
                    }
                    "shareFiles" -> share(args["paths"] as? List<*>, result)
                    "exportFile" -> export(args["name"] as? String, args["path"] as? String, result)
                    "importFile" -> chooseImport(result)
                    "clearTemporaryFiles" -> async(result) {
                        if (documentResult != null) throw IllegalStateException("请先完成文件选择。")
                        var bytes = 0L
                        listOf("posey-share", "posey-import").forEach { name ->
                            File(cacheDir, name).listFiles()?.filter { it.isFile }?.forEach { file -> val size = file.length(); if (file.delete()) bytes += size }
                        }; bytes
                    }
                    "storageUsage" -> async(result) {
                        val roots = listOf(filesDir, File(applicationInfo.dataDir, "app_flutter"), cacheDir)
                        val files = roots.flatMap { it.walkTopDown().filter(File::isFile).toList() }.distinctBy { it.canonicalPath }
                        mapOf("bytes" to files.sumOf(File::length), "recoveryCopies" to files.count { it.name.startsWith("recovery-") })
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.posey.camera/background-ai").setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val id = args["jobId"] as? String ?: ""
            when (call.method) {
                "start" -> {
                    if (!foreground) { result.error("not_foreground", "请在应用内提交生成任务。", null); return@setMethodCallHandler }
                    io.execute {
                        try {
                            val store = PoseyAiStore.get(applicationContext); store.prepare(id, args)
                            runOnUiThread {
                                try { PoseyAiService.start(applicationContext, id); store.accepted(id); result.success(mapOf("jobId" to id)) }
                                catch (_: Exception) { store.safeUpdate(id, "failed", "后台任务未能启动，没有发送生成请求。"); result.error("start_failed", "后台任务未能启动，请重新打开应用后再试。", null) }
                            }
                        } catch (error: Exception) { runOnUiThread { result.error("start_failed", safeMessage(error), null) } }
                    }
                }
                "getJobs" -> async(result) {
                    val store = PoseyAiStore.get(applicationContext)
                    val records = store.records().map { record ->
                        val jobId = record.getString("id")
                        record.put("imageAvailable", store.resultFile(jobId).isFile || store.memoryResults.containsKey(jobId))
                            .put("sourceAvailable", store.sourceFile(jobId).isFile).toMap()
                    }
                    if (foreground && !PoseyAiService.running && store.next() != null) runOnUiThread { try { PoseyAiService.start(applicationContext) } catch (_: Exception) { } }
                    mapOf("jobs" to records)
                }
                "getImage" -> async(result) { PoseyAiStore.get(applicationContext).image(id, args["source"] == true) }
                "cancel", "clear" -> async(result) {
                    require(PoseyAiStore.validId(id))
                    val store = PoseyAiStore.get(applicationContext); store.cancel(id); PoseyAiTransport.get(store).disconnect(id)
                    if (call.method == "clear") store.clear(id)
                    runOnUiThread { if (foreground && PoseyAiService.running) try { PoseyAiService.start(applicationContext) } catch (_: Exception) { } }; null
                }
                "retryResult" -> attempt(result) {
                    require(PoseyAiStore.validId(id))
                    if (!foreground) throw IllegalStateException("请在应用内重试保存成片。")
                    PoseyAiService.start(applicationContext)
                    async(result) {
                        val store = PoseyAiStore.get(applicationContext); PoseyAiTransport.get(store).retryResult(id)
                        runOnUiThread { if (foreground) try { PoseyAiService.start(applicationContext) } catch (_: Exception) { } }; null
                    }
                }
                "repairHistory" -> async(result) { PoseyAiStore.get(applicationContext).repair(); null }
                else -> result.notImplemented()
            }
        }
    }
    override fun onResume() { super.onResume(); foreground = true }
    override fun onPause() { foreground = false; super.onPause() }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent)
        val id = intent.getStringExtra("poseyJobId")?.takeIf(PoseyAiStore::validId) ?: return
        pendingJob = id; platform?.invokeMethod("openJob", id)
    }
    private fun requestNotifications(force: Boolean, result: MethodChannel.Result) = attempt(result) {
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(getSystemService(NotificationManager::class.java).areNotificationsEnabled()); return@attempt
        }
        val prefs = getSharedPreferences("posey.permissions", MODE_PRIVATE)
        if (!force && prefs.getBoolean("askedNotifications", false)) { result.success(false); return@attempt }
        if (notificationResult != null) throw IllegalStateException("正在等待通知授权。")
        notificationResult = result; prefs.edit().putBoolean("askedNotifications", true).apply()
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7813)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7813) { notificationResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED); notificationResult = null }
    }
    private fun owned(path: String?): File {
        val file = File(path ?: "").canonicalFile; val root = File(applicationInfo.dataDir).canonicalFile
        require(file.isFile && file.path.startsWith(root.path + File.separator)) { "文件不可用，请重新选择。" }
        require(file.length() <= limit) { "文件超过 1 GB。" }; return file
    }
    private fun share(paths: List<*>?, result: MethodChannel.Result) {
        asyncWithMain(result, {
            require(!paths.isNullOrEmpty() && paths.size <= 100) { "一次最多分享 100 张照片。" }
            val folder = File(cacheDir, "posey-share").apply { mkdirs() }
            ArrayList(paths.map { value ->
                val source = owned(value as? String); require(source.length() <= 24 * 1024 * 1024) { "照片过大。" }
                val copy = File(folder, "${UUID.randomUUID()}.${source.extension.takeIf { it in setOf("jpg", "jpeg", "png", "webp") } ?: "jpg"}")
                source.copyTo(copy); Uri.Builder().scheme("content").authority("$packageName.files").appendPath(copy.name).build()
            })
        }) { uris ->
            val intent = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
                type = "image/*"
                if (uris.size == 1) putExtra(Intent.EXTRA_STREAM, uris.first()) else putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                clipData = android.content.ClipData.newUri(contentResolver, "Posey", uris.first()).also { clip -> uris.drop(1).forEach { clip.addItem(android.content.ClipData.Item(it)) } }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }; startActivity(Intent.createChooser(intent, "分享照片")); result.success(null)
        }
    }
    private fun export(name: String?, path: String?, result: MethodChannel.Result) = attempt(result) {
        if (documentResult != null) throw IllegalStateException("请先完成文件选择。")
        exportSource = owned(path); documentResult = result
        try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); type = "application/zip"
            putExtra(Intent.EXTRA_TITLE, name?.substringAfterLast('/')?.substringAfterLast('\\')?.take(120) ?: "Posey-backup.zip")
        }, 7811) } catch (error: Exception) { documentResult = null; exportSource = null; throw error }
    }
    private fun chooseImport(result: MethodChannel.Result) = attempt(result) {
        if (documentResult != null) throw IllegalStateException("请先完成文件选择。")
        documentResult = result
        try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*" }, 7812) }
        catch (error: Exception) { documentResult = null; throw error }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode !in setOf(7811, 7812)) return
        val reply = documentResult ?: return; val source = exportSource; val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            documentResult = null; exportSource = null; reply.success(if (requestCode == 7811) false else null); return
        }
        io.execute {
            try {
                val value: Any = if (requestCode == 7811) {
                    require(source != null)
                    contentResolver.openOutputStream(uri, "wt").use { output -> require(output != null); source.inputStream().use { it.copyTo(output) } }; true
                } else {
                    val folder = File(cacheDir, "posey-import").apply { mkdirs() }; val file = File(folder, "${UUID.randomUUID()}.zip")
                    try {
                        contentResolver.openInputStream(uri).use { input ->
                            require(input != null); file.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024); var total = 0L
                                while (true) { val count = input.read(buffer); if (count < 0) break; total += count; require(total <= limit) { "备份超过 1 GB。" }; output.write(buffer, 0, count) }
                            }
                        }; file.path
                    } catch (error: Exception) { file.delete(); throw error }
                }; runOnUiThread { documentResult = null; exportSource = null; reply.success(value) }
            } catch (_: Exception) { runOnUiThread { documentResult = null; exportSource = null; reply.error("file_failed", "文件未能读写，请检查空间与文件访问权限。", null) } }
        }
    }
    private fun safeMessage(error: Exception): String = if (error is IllegalArgumentException || error is IllegalStateException) error.message ?: "操作未完成。" else "操作未完成，请检查存储空间后重试。"
    private fun attempt(result: MethodChannel.Result, block: () -> Unit) { try { block() } catch (error: Exception) { result.error("platform_failed", safeMessage(error), null) } }
    private fun async(result: MethodChannel.Result, block: () -> Any?) { io.execute { try { val value = block(); runOnUiThread { result.success(value) } } catch (error: Exception) { runOnUiThread { result.error("platform_failed", safeMessage(error), null) } } } }
    private fun <T> asyncWithMain(result: MethodChannel.Result, work: () -> T, done: (T) -> Unit) { io.execute { try { val value = work(); runOnUiThread { attempt(result) { done(value) } } } catch (error: Exception) { runOnUiThread { result.error("platform_failed", safeMessage(error), null) } } } }
    private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { name -> jsonValue(get(name)) }
    private fun jsonValue(value: Any?): Any? = when (value) { JSONObject.NULL -> null; is JSONObject -> value.toMap(); is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }; else -> value }
}
