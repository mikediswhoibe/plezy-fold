package com.edde746.plezy.fold

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Process
import android.provider.MediaStore
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.locks.ReentrantLock

/**
 * File sink for fold-detection diagnostics.
 *
 * Mirrors every log line to up to three targets, probed once per process
 * launch:
 *
 * 1. the app's external **media** directory
 *    (`/storage/emulated/0/Android/media/<package>/plezy-fold.log`) — the
 *    app-specific media tree, which file managers expose;
 * 2. the public Downloads directory
 *    (`/storage/emulated/0/Download/plezy-fold-<package>.log`) via
 *    [MediaStore.Downloads] (API 29+, permission-free; the package suffix
 *    keeps side-installed copies of the app from truncating each other on
 *    API levels below 33, where Downloads queries are not app-scoped);
 * 3. the app's external **files** directory
 *    (`/storage/emulated/0/Android/data/<package>/files/plezy-fold.log`) —
 *    unreachable from most file managers, kept as a last resort.
 *
 * Targets that cannot be created at session start are dropped; the init
 * line written to each live target records which targets are live, so the
 * log always says where to look. The file is truncated once per *process*
 * launch, not per activity recreation. All writers (the native monitor, the
 * Dart-side log channel) go through [append], which is lock-guarded; write
 * failures are swallowed because diagnostics must never take the app down.
 */
class FoldLogSink internal constructor(
  private val mediaFile: File?,
  private val dataFile: File?,
  private val downloadUri: Uri?,
  private val context: Context,
) {

  private val lock = ReentrantLock()

  /** Appends one line to every live target, prefixed with a local timestamp and [source]. */
  fun append(source: String, message: String) {
    val line = "${timestamp()} [$source] $message\n"
    lock.lock()
    try {
      mediaFile?.appendText(line)
      dataFile?.appendText(line)
      appendToDownloads(line)
    } catch (_: Exception) {
      // Diagnostics must never crash the app.
    } finally {
      lock.unlock()
    }
  }

  private fun appendToDownloads(line: String) {
    val uri = downloadUri ?: return
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
    runCatching {
      // "wa" keeps the previous process's lines.
      context.contentResolver.openOutputStream(uri, "wa")?.use { it.write(line.toByteArray()) }
    }
  }

  companion object {
    private const val LOG_FILE_NAME = "plezy-fold.log"
    private const val TIMESTAMP_FORMAT = "yyyy-MM-dd HH:mm:ss.SSS"

    @Volatile private var processSessionStarted = false

    /**
     * Returns this process's sink, truncating the log exactly once per
     * process launch. Null when no target is available.
     */
    @Synchronized
    fun forProcess(context: Context): FoldLogSink? {
      val pkg = context.packageName
      // The app-specific trees live under the external storage root that
      // getExternalFilesDir() sits in: <ext>/Android/data/<pkg>/files ->
      // four levels up is <ext>, and <ext>/Android/media/<pkg> is the
      // app-specific media sibling (unlike getExternalFilesDir
      // (DIRECTORY_DOWNLOADS), which is just <ext>/Android/data/<pkg>/files/Download).
      val dataFilesDir = context.getExternalFilesDir(null)
      val dataFile = dataFilesDir?.let { File(it, LOG_FILE_NAME) }
      val mediaFile = dataFilesDir?.parentFile?.parentFile?.parentFile?.parentFile
        ?.let { File(it, "Android/media/$pkg/$LOG_FILE_NAME") }

      val downloadName = "plezy-fold-$pkg.log"
      val downloadUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        downloadsUri(context, downloadName)
      } else {
        null
      }

      if (mediaFile == null && dataFile == null && downloadUri == null) return null

      if (!processSessionStarted) {
        processSessionStarted = true
        val header =
          "=== plezy fold evidence log ===\n" +
            "pid=${Process.myPid()} sdk=${Build.VERSION.SDK_INT} model=${Build.MODEL}\n"
        runCatching {
          mediaFile?.let { file ->
            file.parentFile?.mkdirs()
            file.writeText(header)
          }
          dataFile?.let { file ->
            file.parentFile?.mkdirs()
            file.writeText(header)
          }
        }
        runCatching {
          if (downloadUri != null) {
            context.contentResolver.openOutputStream(downloadUri)?.use { it.write(header.toByteArray()) }
          }
        }
      }

      val summary =
        "media=${mediaFile != null} downloads=${downloadUri != null} data=${dataFile != null}\n" +
          "paths:\n" +
          "  media: ${mediaFile?.absolutePath ?: "(unavailable)"}\n" +
          "  downloads: ${downloadUri?.let { "/storage/emulated/0/Download/$downloadName" } ?: "(unavailable)"}\n" +
          "  data: ${dataFile?.absolutePath ?: "(unavailable)"}"
      return FoldLogSink(mediaFile, dataFile, downloadUri, context).also {
        it.append("native", "sink init: $summary")
      }
    }

    /**
     * Finds (or creates) the app's [MediaStore.Downloads] file and returns a
     * content URI for it. On API 33+ the query only sees this app's files;
     * below that it is scoped to this package's Downloads subdirectory.
     */
    private fun downloadsUri(context: Context, fileName: String): Uri? = runCatching {
      val projection = arrayOf(MediaStore.Downloads._ID)
      val selection = "${MediaStore.Downloads.DISPLAY_NAME} = ?"
      val selectionArgs = arrayOf(fileName)
      val existingId = context.contentResolver
        .query(MediaStore.Downloads.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, null)
        ?.use { cursor -> if (cursor.moveToFirst()) cursor.getLong(0) else 0L }
        ?: 0L
      if (existingId != 0L) {
        Uri.parse("content://media/external/downloads/$existingId")
      } else {
        val values = ContentValues().apply {
          put(MediaStore.Downloads.DISPLAY_NAME, fileName)
          put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
          put(MediaStore.Downloads.MIME_TYPE, "text/plain")
        }
        context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
      }
    }.getOrNull()

    private fun timestamp(): String = SimpleDateFormat(TIMESTAMP_FORMAT, Locale.US).format(Date())
  }
}