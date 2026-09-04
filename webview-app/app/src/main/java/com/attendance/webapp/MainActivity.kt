package com.attendance.webapp

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var web: WebView
    private lateinit var offlineBox: LinearLayout
    private var fileCb: ValueCallback<Array<Uri>>? = null

    private val filePicker = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { res ->
        if (res.resultCode == Activity.RESULT_OK) {
            val uris = mutableListOf<Uri>()
            res.data?.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            }
            res.data?.data?.let { uris.add(it) }
            fileCb?.onReceiveValue(uris.toTypedArray())
        } else {
            fileCb?.onReceiveValue(null)
        }
        fileCb = null
    }

    private fun baseUrl(): String {
        val p = getSharedPreferences("app", Context.MODE_PRIVATE)
        return p.getString("base", BuildConfig.DEFAULT_BASE_URL)
            ?: BuildConfig.DEFAULT_BASE_URL
    }

    private fun loadHome() {
        offlineBox.visibility = View.GONE
        web.loadUrl(baseUrl().trimEnd('/') + "/app/")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        web = findViewById(R.id.web)
        offlineBox = findViewById(R.id.offlineBox)

        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            loadWithOverviewMode = true
            useWideViewPort = true
        }
        web.webViewClient = object : WebViewClient() {
            override fun onReceivedError(
                view: WebView, request: WebResourceRequest, error: WebResourceError
            ) {
                if (request.isForMainFrame) offlineBox.visibility = View.VISIBLE
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                view: WebView, filePathCallback: ValueCallback<Array<Uri>>,
                fileChooserParams: FileChooserParams
            ): Boolean {
                fileCb?.onReceiveValue(null)
                fileCb = filePathCallback
                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                }
                filePicker.launch(Intent.createChooser(intent, "Photo chuno"))
                return true
            }
        }
        findViewById<Button>(R.id.btnRetry).setOnClickListener { loadHome() }
        findViewById<Button>(R.id.btnServer).setOnClickListener { serverDialog() }
        if (savedInstanceState != null) web.restoreState(savedInstanceState)
        else loadHome()
    }

    private fun serverDialog() {
        val inp = EditText(this)
        inp.setText(baseUrl())
        AlertDialog.Builder(this)
            .setTitle("Server URL")
            .setView(inp)
            .setPositiveButton("Save") { _, _ ->
                val v = inp.text.toString().trim().trimEnd('/')
                if (v.isNotEmpty()) {
                    getSharedPreferences("app", Context.MODE_PRIVATE)
                        .edit().putString("base", v).apply()
                    loadHome()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        web.saveState(outState)
    }

    @Deprecated("back handling")
    override fun onBackPressed() {
        if (::web.isInitialized && web.canGoBack()) web.goBack()
        else super.onBackPressed()
    }
}
