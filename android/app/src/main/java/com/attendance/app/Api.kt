package com.attendance.app

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Minimal JSON API client (no extra deps) for the Attendance FastAPI backend. */
object Api {
    var base: String = ""
    var token: String = ""

    private suspend fun req(
        path: String,
        method: String = "GET",
        body: String? = null,
        extraHeaders: Map<String, String> = emptyMap(),
    ): Pair<Int, String> = withContext(Dispatchers.IO) {
        val url = URL(base.trimEnd('/') + path)
        val c = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15000
            readTimeout = 30000
            if (token.isNotEmpty()) setRequestProperty("X-Token", token)
            extraHeaders.forEach { (k, v) -> setRequestProperty(k, v) }
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                outputStream.use { it.write(body.toByteArray()) }
            }
        }
        val code = c.responseCode
        val stream = if (code in 200..299) c.inputStream else c.errorStream
        val text = stream?.bufferedReader()?.readText() ?: ""
        c.disconnect()
        code to text
    }

    private fun errMsg(code: Int, text: String): String {
        return try {
            val d = JSONObject(text).opt("detail")
            if (d is JSONObject) d.optString("message", d.optString("code")) else d.toString()
        } catch (e: Exception) {
            "Error $code"
        }
    }

    private fun ok(code: Int, text: String): JSONObject {
        if (code !in 200..299) throw Exception(errMsg(code, text))
        return JSONObject(text)
    }

    suspend fun login(uid: String, roll: String, pw: String? = null): JSONObject {
        val b = JSONObject().put("unique_id", uid).put("roll_no", roll)
        if (pw != null) b.put("password", pw)
        val (code, text) = req("/login", "POST", b.toString())
        return ok(code, text)
    }

    suspend fun register(naam: String, branch: String, year: String, roll: String): JSONObject {
        val b = JSONObject().put("naam", naam).put("branch", branch)
            .put("year", year).put("roll_no", roll)
        val (code, text) = req("/register", "POST", b.toString())
        return ok(code, text)
    }

    suspend fun setPassword(uid: String, roll: String, pw: String): JSONObject {
        val b = JSONObject().put("unique_id", uid).put("roll_no", roll).put("password", pw)
        val (code, text) = req("/admin/set-password", "POST", b.toString())
        return ok(code, text)
    }

    suspend fun forgot(uid: String, roll: String): JSONObject {
        val b = JSONObject().put("unique_id", uid).put("roll_no", roll)
        val (code, text) = req("/admin/forgot-password", "POST", b.toString())
        return ok(code, text)
    }

    suspend fun resetPw(uid: String, roll: String, code: String, npw: String): JSONObject {
        val b = JSONObject().put("unique_id", uid).put("roll_no", roll)
            .put("code", code).put("new_password", npw)
        val (code2, text) = req("/admin/reset-password", "POST", b.toString())
        return ok(code2, text)
    }

    suspend fun calendar(year: Int, month: Int): JSONObject {
        val (code, text) = req("/calendar?year=$year&month=$month")
        return ok(code, text)
    }

    suspend fun stats(): JSONObject {
        val (code, text) = req("/stats")
        return ok(code, text)
    }

    suspend fun mark(status: String): JSONObject {
        val (code, text) = req("/attendance", "POST",
            JSONObject().put("status", status).toString())
        return ok(code, text)
    }

    suspend fun record(date: String): JSONObject {
        val (code, text) = req("/record?date=" + java.net.URLEncoder.encode(date, "UTF-8"))
        return ok(code, text)
    }

    suspend fun proofBytes(date: String, thumb: Boolean): Pair<String, ByteArray> =
        withContext(Dispatchers.IO) {
            val url = URL(base.trimEnd('/') + "/holiday-proof?date=" +
                java.net.URLEncoder.encode(date, "UTF-8") + (if (thumb) "&thumb=1" else ""))
            val c = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 30000
                if (token.isNotEmpty()) setRequestProperty("X-Token", token)
            }
            val code = c.responseCode
            val ct = c.getHeaderField("Content-Type") ?: ""
            val bytes = (if (code in 200..299) c.inputStream else c.errorStream)?.readBytes() ?: ByteArray(0)
            c.disconnect()
            if (code !in 200..299) throw Exception("Error $code")
            ct to bytes
        }

    suspend fun chat(text: String): JSONObject {
        val (code, body) = req("/chat", "POST",
            JSONObject().put("text", text).toString())
        return ok(code, body)
    }

    suspend fun adminCount(): JSONObject {
        val (code, text) = req("/admin/count")
        return ok(code, text)
    }

    suspend fun adminLookup(key: String): JSONObject {
        val (code, text) = req("/admin/lookup?key=" + java.net.URLEncoder.encode(key, "UTF-8"))
        return ok(code, text)
    }

    suspend fun adminRecall(date: String): JSONObject {
        val (code, text) = req("/admin/recall", "POST",
            JSONObject().put("date", date).toString())
        return ok(code, text)
    }
}
