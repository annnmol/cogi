package com.anmoltanwar.cogi

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.anmoltanwar.cogi.ui.theme.CogiTheme

class MainActivity : ComponentActivity() {
    private lateinit var storage: StorageService
    private lateinit var clipboard: ClipboardService
    private var resumed = false
    private val copyError = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        storage = StorageService.get(this)
        clipboard = ClipboardService(this, storage::add)
        enableEdgeToEdge()
        setContent {
            val history by storage.history.collectAsState()
            val storageError by storage.error.collectAsState()
            CogiTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    ClipboardScreen(
                        history = history,
                        error = copyError.value ?: storageError,
                        onCopy = { item ->
                            if (clipboard.copy(item.text)) {
                                copyError.value = null
                                storage.promote(item.id)
                            } else {
                                copyError.value = "Could not copy to the system clipboard."
                            }
                        },
                        modifier = Modifier.padding(innerPadding)
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        clipboard.start()
        if (hasWindowFocus()) clipboard.capture()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && resumed) clipboard.capture()
    }

    override fun onPause() {
        resumed = false
        clipboard.stop()
        super.onPause()
    }
}

@Composable
private fun ClipboardScreen(
    history: List<ClipboardItem>,
    error: String?,
    onCopy: (ClipboardItem) -> Unit,
    modifier: Modifier = Modifier
) {
    var query by rememberSaveable { mutableStateOf("") }
    var draft by rememberSaveable { mutableStateOf("") }
    val visibleHistory = history.filter { it.text.contains(query, ignoreCase = true) }

    Column(
        modifier = modifier.fillMaxSize().imePadding().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Cogi", style = MaterialTheme.typography.headlineMedium)
        Text("Recent", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("Search history") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        if (error != null) Text(error, color = MaterialTheme.colorScheme.error)
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (visibleHistory.isEmpty()) {
                item {
                    Text(if (query.isEmpty()) "No clipboard history yet." else "No matching items.")
                }
            }
            items(visibleHistory, key = { it.id }) { item ->
                Card(onClick = { onCopy(item) }, modifier = Modifier.fillMaxWidth()) {
                    Text(
                        item.text,
                        modifier = Modifier.padding(12.dp),
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            placeholder = { Text("Type something...") },
            maxLines = 4,
            modifier = Modifier.fillMaxWidth()
        )
        Button(onClick = {}, modifier = Modifier.fillMaxWidth()) {
            Text("Send")
        }
    }
}
