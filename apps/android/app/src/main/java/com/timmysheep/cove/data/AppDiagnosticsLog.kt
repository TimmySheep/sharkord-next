package com.timmysheep.cove.data

import android.content.Context
import android.os.Build
import android.util.Log
import com.timmysheep.cove.BuildConfig
import java.io.File
import java.time.Instant

internal class DiagnosticLogStore(
    private val directory: File,
    private val maximumFileBytes: Long = 512 * 1024
) {
    private val currentFile = File(directory, "current.log")
    private val previousFile = File(directory, "previous.log")

    @Synchronized
    fun append(level: String, category: String, message: String, details: String? = null) {
        runCatching {
            directory.mkdirs()
            val line = buildString {
                append(Instant.now())
                append(" ")
                append(level)
                append(" [")
                append(category)
                append("] ")
                append(sanitize(message))
                details?.takeIf(String::isNotBlank)?.let {
                    append('\n')
                    append(sanitize(it))
                }
                append('\n')
            }
            val encoded = line.toByteArray(Charsets.UTF_8)
            if (currentFile.length() + encoded.size > maximumFileBytes) {
                previousFile.delete()
                if (!currentFile.renameTo(previousFile)) currentFile.writeText("")
            }
            currentFile.appendBytes(encoded)
        }
    }

    @Synchronized
    fun exportText(): String = listOf(previousFile, currentFile)
        .filter(File::isFile)
        .joinToString(separator = "\n") { it.readText() }

    @Synchronized
    fun previewText(maximumCharacters: Int): String = exportText().takeLast(maximumCharacters)

    internal fun sanitize(value: String): String {
        val bearerRedacted = bearerToken.replace(value, "$1[REDACTED]")
        val assignmentRedacted = secretAssignment.replace(bearerRedacted) { match ->
            "${match.groupValues[1]}[REDACTED]"
        }
        val queryRedacted = secretQuery.replace(assignmentRedacted) { match ->
            "${match.groupValues[1]}[REDACTED]"
        }
        return queryRedacted.take(MAX_ENTRY_CHARACTERS)
    }

    private companion object {
        const val MAX_ENTRY_CHARACTERS = 24_000
        val secretAssignment = Regex(
            """(?i)([\"']?(?:password|serverpassword|token|accesstoken|refreshtoken|authorization|cookie|secret)[\"']?\s*[:=]\s*[\"']?)([^\"'&\s,;}]+)"""
        )
        val secretQuery = Regex(
            """(?i)([?&](?:password|serverpassword|token|accesstoken|refreshtoken|authorization|cookie|secret)=)[^&\s]+"""
        )
        val bearerToken = Regex("(?i)(Bearer\\s+)[A-Za-z0-9._~+/-]+=*")
    }
}

@PublishedApi
internal object AppDiagnosticsLog {
    private val lock = Any()
    @Volatile private var store: DiagnosticLogStore? = null
    private var previousExceptionHandler: Thread.UncaughtExceptionHandler? = null
    private var exceptionHandlerInstalled = false

    fun initialize(context: Context) {
        synchronized(lock) {
            if (store == null) {
                store = DiagnosticLogStore(File(context.applicationContext.filesDir, "diagnostics"))
                store?.append(
                    level = "INFO",
                    category = "app",
                    message = "started version=${BuildConfig.VERSION_NAME} build=${BuildConfig.VERSION_CODE} android=${Build.VERSION.SDK_INT} device=${Build.MODEL}"
                )
            }
            if (!exceptionHandlerInstalled) {
                previousExceptionHandler = Thread.getDefaultUncaughtExceptionHandler()
                Thread.setDefaultUncaughtExceptionHandler { thread, error ->
                    store?.append(
                        level = "FATAL",
                        category = "crash",
                        message = "uncaught exception on ${thread.name}",
                        details = error.stackTraceToString()
                    )
                    previousExceptionHandler?.uncaughtException(thread, error)
                }
                exceptionHandlerInstalled = true
            }
        }
    }

    fun info(category: String, message: String) = record("INFO", category, message)

    fun warning(category: String, message: String) = record("WARN", category, message)

    @PublishedApi
    internal fun error(category: String, message: String, error: Throwable? = null) {
        record("ERROR", category, message, error?.stackTraceToString())
    }

    fun exportText(context: Context): String {
        initialize(context)
        return store?.exportText().orEmpty()
    }

    fun previewText(context: Context): String {
        initialize(context)
        return store?.previewText(12_000).orEmpty()
    }

    private fun record(level: String, category: String, message: String, details: String? = null) {
        val activeStore = store
        if (activeStore == null) {
            Log.w("CoveDiagnostics", "log skipped before initialization")
            return
        }
        activeStore.append(level, category, message, details)
    }
}
