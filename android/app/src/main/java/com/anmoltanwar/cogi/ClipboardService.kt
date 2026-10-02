package com.anmoltanwar.cogi

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context

/** Observes text only while the activity is resumed; Android controls read access. */
class ClipboardService(context: Context, private val onText: (String) -> Unit) {
    private val clipboard = context.getSystemService(ClipboardManager::class.java)
    private var observing = false
    private var lastText: String? = null
    private val listener = ClipboardManager.OnPrimaryClipChangedListener { capture() }

    fun start() {
        if (!observing) {
            clipboard.addPrimaryClipChangedListener(listener)
            observing = true
        }
    }

    fun stop() {
        if (observing) {
            clipboard.removePrimaryClipChangedListener(listener)
            observing = false
        }
    }

    fun capture() {
        if (!observing) return
        val text = try {
            val clip = clipboard.primaryClip ?: return
            if (!clip.description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) ||
                clip.itemCount == 0
            ) {
                lastText = null
                return
            }
            // Do not coerce URIs or intents into text or read their contents.
            clip.getItemAt(0).text?.toString()
        } catch (_: SecurityException) {
            return
        }
        if (text.isNullOrEmpty()) {
            lastText = null
            return
        }
        if (text != lastText) {
            lastText = text
            onText(text)
        }
    }

    fun copy(text: String): Boolean {
        val previous = lastText
        lastText = text
        return try {
            clipboard.setPrimaryClip(ClipData.newPlainText("Cogi", text))
            true
        } catch (_: SecurityException) {
            lastText = previous
            false
        }
    }
}
