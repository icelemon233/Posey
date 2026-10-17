package com.posey.camera

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

class PoseyFileProvider : ContentProvider() {
    override fun onCreate() = true
    private fun resolve(uri: Uri): File {
        require(uri.pathSegments.size == 1)
        val folder = File(requireNotNull(context).cacheDir, "posey-share").canonicalFile
        val file = File(folder, uri.pathSegments.single()).canonicalFile
        require(file.parentFile == folder && file.isFile); return file
    }
    override fun getType(uri: Uri): String = when (resolve(uri).extension) { "png" -> "image/png"; "webp" -> "image/webp"; else -> "image/jpeg" }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val file = resolve(uri)
        val columns = projection?.filter { it == OpenableColumns.DISPLAY_NAME || it == OpenableColumns.SIZE } ?: listOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns.toTypedArray()).apply { addRow(columns.map { if (it == OpenableColumns.SIZE) file.length() else file.name }) }
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor { require(mode == "r"); return ParcelFileDescriptor.open(resolve(uri), ParcelFileDescriptor.MODE_READ_ONLY) }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
}
