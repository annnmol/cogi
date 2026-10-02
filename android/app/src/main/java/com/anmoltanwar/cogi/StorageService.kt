package com.anmoltanwar.cogi

import android.content.Context
import android.util.AtomicFile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

data class ClipboardItem(val id: String, val text: String, val timestamp: Long)

/** One application-scoped queue keeps loading, history changes and disk writes in order. */
class StorageService private constructor(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "clipboard-history.json"))
    private val executor = Executors.newSingleThreadExecutor()
    private val mutableHistory = MutableStateFlow<List<ClipboardItem>>(emptyList())
    val history: StateFlow<List<ClipboardItem>> = mutableHistory.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = mutableError.asStateFlow()

    init {
        executor.execute {
            try {
                val entries = JSONArray(file.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() })
                val loaded = mutableListOf<ClipboardItem>()
                for (index in 0 until entries.length()) {
                    val entry = entries.getJSONObject(index)
                    val text = entry.getString("text")
                    if (text.isNotEmpty() && loaded.none { it.text == text }) {
                        loaded.add(ClipboardItem(entry.getString("id"), text, entry.getLong("timestamp")))
                    }
                    if (loaded.size == HISTORY_LIMIT) break
                }
                mutableHistory.value = loaded
            } catch (_: FileNotFoundException) {
                // First launch has no history file. openRead also handles AtomicFile recovery.
            } catch (_: IOException) {
                mutableError.value = "Could not load clipboard history."
            } catch (_: JSONException) {
                mutableError.value = "Could not load clipboard history."
            }
        }
    }

    fun add(text: String) {
        if (text.isEmpty()) return
        executor.execute {
            val current = mutableHistory.value
            if (current.firstOrNull()?.text == text) return@execute
            val item = current.firstOrNull { it.text == text }
                ?: ClipboardItem(UUID.randomUUID().toString(), text, System.currentTimeMillis())
            save(listOf(item.copy(timestamp = System.currentTimeMillis())) + current.filter { it.id != item.id })
        }
    }

    fun promote(id: String) {
        executor.execute {
            val current = mutableHistory.value
            val item = current.firstOrNull { it.id == id } ?: return@execute
            save(listOf(item.copy(timestamp = System.currentTimeMillis())) + current.filter { it.id != id })
        }
    }

    private fun save(items: List<ClipboardItem>) {
        val latest = items.take(HISTORY_LIMIT)
        val entries = JSONArray()
        latest.forEach { item ->
            entries.put(JSONObject().put("id", item.id).put("text", item.text).put("timestamp", item.timestamp))
        }
        try {
            val stream = file.startWrite()
            try {
                stream.write(entries.toString().toByteArray(Charsets.UTF_8))
                file.finishWrite(stream)
            } catch (exception: IOException) {
                file.failWrite(stream)
                throw exception
            }
            mutableHistory.value = latest
            mutableError.value = null
        } catch (_: IOException) {
            mutableError.value = "Could not save clipboard history."
        }
    }

    companion object {
        const val HISTORY_LIMIT = 30
        @Volatile private var instance: StorageService? = null

        fun get(context: Context): StorageService = instance ?: synchronized(this) {
            instance ?: StorageService(context.applicationContext).also { instance = it }
        }
    }
}
