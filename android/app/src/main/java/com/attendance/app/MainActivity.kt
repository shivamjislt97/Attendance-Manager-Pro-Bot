package com.attendance.app

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.Calendar

class MainActivity : AppCompatActivity() {
    private val scope = MainScope()
    private var calY = 0
    private var calM = 0
    private var profile: JSONObject? = null
    private var lpUid = ""
    private var lpRoll = ""
    private var recallArmed = ""
    private val cache = mutableMapOf<String, JSONObject>()

    private fun v(id: Int): View = findViewById(id)
    private fun tv(id: Int): TextView = findViewById(id)
    private fun et(id: Int): EditText = findViewById(id)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val prefs = getSharedPreferences("app", Context.MODE_PRIVATE)
        Api.base = prefs.getString("base", "")!!
        if (Api.base.isEmpty()) {
            Api.base = "https://cookies-december-firm-hartford.trycloudflare.com"
        }

        // ---- login ----
        findViewById<Button>(R.id.btnLogin).setOnClickListener {
            lpUid = et(R.id.inUid).text.toString().trim()
            lpRoll = et(R.id.inRoll).text.toString().trim()
            hideLoginBlocks()
            scope.launch {
                try {
                    enterApp(Api.login(lpUid, lpRoll))
                } catch (e: Exception) {
                    val msg = e.message ?: ""
                    if (msg.contains("password_not_set") || msg.contains("pehle admin password")) {
                        v(R.id.loginSetBlock).visibility = View.VISIBLE
                        tv(R.id.loginErr).text = "🔑 $msg"
                    } else if (msg.contains("password_required") || msg.contains("Admin password")) {
                        v(R.id.loginPwBlock).visibility = View.VISIBLE
                        tv(R.id.loginErr).text = "🔒 Admin hai — password do 👇"
                    } else tv(R.id.loginErr).text = "❌ $msg"
                }
            }
        }
        findViewById<Button>(R.id.btnPwLogin).setOnClickListener {
            scope.launch {
                try {
                    enterApp(Api.login(lpUid, lpRoll, et(R.id.inPw).text.toString()))
                } catch (e: Exception) {
                    tv(R.id.pwErr).text = "❌ ${e.message}"
                }
            }
        }
        findViewById<TextView>(R.id.linkForgot).setOnClickListener {
            hideLoginBlocks(); v(R.id.loginForgotBlock).visibility = View.VISIBLE
        }
        findViewById<Button>(R.id.btnSetPw).setOnClickListener {
            val p1 = et(R.id.inNewPw1).text.toString()
            if (p1 != et(R.id.inNewPw2).text.toString()) {
                tv(R.id.setErr).text = "❌ Dono password same likho"; return@setOnClickListener
            }
            scope.launch {
                try {
                    Api.setPassword(lpUid, lpRoll, p1)
                    et(R.id.inPw).setText(p1)
                    hideLoginBlocks(); v(R.id.loginPwBlock).visibility = View.VISIBLE
                    tv(R.id.loginErr).text = "✅ Password set! Ab Admin Login dabao 👇"
                } catch (e: Exception) {
                    tv(R.id.setErr).text = "❌ ${e.message}"
                }
            }
        }
        findViewById<Button>(R.id.btnGetCode).setOnClickListener {
            scope.launch {
                try {
                    Api.forgot(lpUid, lpRoll)
                    tv(R.id.forgotMsg).text = "✅ Code Telegram par bhej diya! 📩"
                } catch (e: Exception) {
                    tv(R.id.forgotErr).text = "❌ ${e.message}"
                }
            }
        }
        findViewById<Button>(R.id.btnResetPw).setOnClickListener {
            scope.launch {
                try {
                    Api.resetPw(lpUid, lpRoll, et(R.id.inCode).text.toString().trim(),
                        et(R.id.inResetPw).text.toString())
                    tv(R.id.forgotMsg).text = "✅ Password reset! Ab password se login karo 👇"
                    hideLoginBlocks(); v(R.id.loginPwBlock).visibility = View.VISIBLE
                } catch (e: Exception) {
                    tv(R.id.forgotErr).text = "❌ ${e.message}"
                }
            }
        }
        findViewById<TextView>(R.id.linkRegister).setOnClickListener {
            hideLoginBlocks(); v(R.id.loginRegBlock).visibility = View.VISIBLE
        }
        findViewById<Button>(R.id.btnRegister).setOnClickListener {
            scope.launch {
                try {
                    val r = Api.register(
                        et(R.id.inRNaam).text.toString(),
                        et(R.id.inRBranch).text.toString(),
                        et(R.id.inRYear).text.toString(),
                        et(R.id.inRRoll).text.toString())
                    tv(R.id.regOk).text = "🎉 COMPLETE! 🆔 " + r.getString("unique_id")
                    et(R.id.inUid).setText(r.getString("unique_id"))
                    et(R.id.inRoll).setText(r.getString("roll_no"))
                } catch (e: Exception) {
                    tv(R.id.regErr).text = "❌ ${e.message}"
                }
            }
        }
        tv(R.id.txtBase).text = "⚙️ Server: ${Api.base} (badalne ke liye tap karo)"
        tv(R.id.txtBase).setOnClickListener {
            val inp = EditText(this); inp.setText(Api.base)
            AlertDialog.Builder(this).setTitle("Server URL").setView(inp)
                .setPositiveButton("Save") { _, _ ->
                    Api.base = inp.text.toString().trim().trimEnd('/')
                    prefs.edit().putString("base", Api.base).apply()
                    tv(R.id.txtBase).text = "⚙️ Server: ${Api.base}"
                }.setNegativeButton("Cancel", null).show()
        }

        // ---- nav ----
        findViewById<Button>(R.id.navHome).setOnClickListener { show("home") }
        findViewById<Button>(R.id.navCal).setOnClickListener { show("cal") }
        findViewById<Button>(R.id.navStats).setOnClickListener { show("stats") }
        findViewById<Button>(R.id.navChat).setOnClickListener { show("chat") }
        findViewById<Button>(R.id.navAdmin).setOnClickListener { show("admin") }
        findViewById<Button>(R.id.navExit).setOnClickListener {
            AlertDialog.Builder(this)
                .setMessage("⚠️ Account logout ho jayega! Kya logout karna hai?")
                .setPositiveButton("✅ HAA") { _, _ -> doLogout() }
                .setNegativeButton("❌ NHI", null).show()
        }

        // ---- home ----
        findViewById<Button>(R.id.btnPresent).setOnClickListener { markIt("PRESENT") }
        findViewById<Button>(R.id.btnChhutti).setOnClickListener { markIt("CHHUTTI") }
        findViewById<Button>(R.id.btnMaze).setOnClickListener { loadHome(true) }

        // ---- calendar ----
        findViewById<Button>(R.id.calPrev).setOnClickListener {
            calM--; if (calM < 1) { calM = 12; calY-- }; loadCal()
        }
        findViewById<Button>(R.id.calNext).setOnClickListener {
            calM++; if (calM > 12) { calM = 1; calY++ }; loadCal()
        }

        // ---- chat ----
        val qs = listOf("0", "1", "2", "3", "4", "5", "6", "7")
        val chips = findViewById<GridLayout>(R.id.chips)
        qs.forEach { q ->
            val b = Button(this); b.text = q
            b.setOnClickListener { sendChat(q) }
            chips.addView(b)
        }
        findViewById<Button>(R.id.btnChat).setOnClickListener {
            val t = et(R.id.inChat).text.toString().trim()
            if (t.isNotEmpty()) { et(R.id.inChat).setText(""); sendChat(t) }
        }

        // ---- admin ----
        findViewById<Button>(R.id.btnCount).setOnClickListener {
            scope.launch {
                try {
                    val c = Api.adminCount()
                    tv(R.id.countOut).visibility = View.VISIBLE
                    tv(R.id.countOut).text = "👥 Total: ${c.getInt("total")}\n" +
                        "🏷️ ${c.getJSONObject("by_branch")}\n🎓 ${c.getJSONObject("by_year")}"
                } catch (e: Exception) {
                    tv(R.id.countOut).visibility = View.VISIBLE
                    tv(R.id.countOut).text = "❌ ${e.message}"
                }
            }
        }
        findViewById<Button>(R.id.btnLookup).setOnClickListener {
            scope.launch {
                try {
                    val r = Api.adminLookup(et(R.id.inLookup).text.toString().trim())
                    val st = r.getJSONObject("student"); val s = r.getJSONObject("stats")
                    tv(R.id.lookupOut).visibility = View.VISIBLE
                    tv(R.id.lookupOut).text = "👤 ${st.getString("naam")} | " +
                        "${st.getString("roll_no")}\n📊 ${s.getDouble("percent")}%"
                } catch (e: Exception) {
                    tv(R.id.lookupOut).visibility = View.VISIBLE
                    tv(R.id.lookupOut).text = "❌ ${e.message}"
                }
            }
        }
        findViewById<Button>(R.id.btnPreview).setOnClickListener { holidaySubmit(true) }
        findViewById<Button>(R.id.btnHoliday).setOnClickListener { holidaySubmit(false) }
        findViewById<Button>(R.id.btnRecall).setOnClickListener {
            val day = et(R.id.inRecall).text.toString().trim()
            if (recallArmed != day) {
                recallArmed = day
                tv(R.id.recallOut).visibility = View.VISIBLE
                tv(R.id.recallOut).text = "⚠️ Pakka? $day ka broadcast delete hoga. Confirm: dobara dabao."
                return@setOnClickListener
            }
            recallArmed = ""
            scope.launch {
                try {
                    val r = Api.adminRecall(day)
                    tv(R.id.recallOut).text = "🗑️ Deleted: ${r.getInt("deleted")} | Failed: ${r.getInt("failed")}"
                } catch (e: Exception) {
                    tv(R.id.recallOut).text = "❌ ${e.message}"
                }
            }
        }

        // auto-login
        val tok = prefs.getString("token", "")
        val prof = prefs.getString("profile", "")
        if (!tok.isNullOrEmpty() && !prof.isNullOrEmpty()) {
            Api.token = tok
            profile = JSONObject(prof)
            enterAppUi()
        }
    }

    private fun hideLoginBlocks() {
        listOf(R.id.loginPwBlock, R.id.loginSetBlock, R.id.loginForgotBlock, R.id.loginRegBlock)
            .forEach { v(it).visibility = View.GONE }
    }

    private fun enterApp(d: JSONObject) {
        Api.token = d.getString("token")
        profile = d
        getSharedPreferences("app", Context.MODE_PRIVATE).edit()
            .putString("token", Api.token).putString("profile", d.toString()).apply()
        enterAppUi()
    }

    private fun enterAppUi() {
        v(R.id.scrLogin).visibility = View.GONE
        v(R.id.navBar).visibility = View.VISIBLE
        v(R.id.navAdmin).visibility =
            if (profile?.optBoolean("is_admin") == true) View.VISIBLE else View.GONE
        show("home")
    }

    private fun doLogout() {
        Api.token = ""; profile = null; cache.clear()
        getSharedPreferences("app", Context.MODE_PRIVATE).edit()
            .remove("token").remove("profile").apply()
        v(R.id.navBar).visibility = View.GONE
        listOf(R.id.scrHome, R.id.scrCal, R.id.scrStats, R.id.scrChat, R.id.scrAdmin)
            .forEach { v(it).visibility = View.GONE }
        v(R.id.scrLogin).visibility = View.VISIBLE
    }

    private fun show(which: String) {
        mapOf("home" to R.id.scrHome, "cal" to R.id.scrCal, "stats" to R.id.scrStats,
            "chat" to R.id.scrChat, "admin" to R.id.scrAdmin).forEach { (k, id) ->
            v(id).visibility = if (k == which) View.VISIBLE else View.GONE
        }
        when (which) {
            "home" -> loadHome()
            "cal" -> loadCal()
            "stats" -> loadStats()
        }
    }

    private fun todayStr(): String {
        val c = Calendar.getInstance()
        return "%02d/%02d/%04d".format(c.get(Calendar.DAY_OF_MONTH), c.get(Calendar.MONTH) + 1, c.get(Calendar.YEAR))
    }

    private fun loadHome(force: Boolean = false) {
        tv(R.id.homeHi).text = "😎 Namaste, ${profile?.optString("naam") ?: "Dost"}!"
        tv(R.id.homeDate).text = "📅 Aaj: ${todayStr()}"
        val key = "home:${todayStr()}"
        if (!force && cache.containsKey(key)) { paintHome(cache[key]!!); return }
        tv(R.id.homeStatus).text = "⏳..."
        scope.launch {
            try {
                val r = Api.record(todayStr())
                cache[key] = r; paintHome(r)
            } catch (e: Exception) {
                tv(R.id.homeStatus).text = "❌ ${e.message}"
            }
        }
    }

    private fun paintHome(r: JSONObject) {
        val st = r.optString("status", "")
        val hol = r.optBoolean("holiday", false)
        tv(R.id.homeStatus).text = if (st.isNotEmpty()) "✅ Aaj ka status: $st"
            else if (hol) "🏖️ AAJ TOH CHHUTTI HAI MOZ KARO 🎉" else "⏰ Aaj ki attendance abhi nahi lagi"
        val maze = st.isEmpty() && hol
        v(R.id.btnMaze).visibility = if (maze) View.VISIBLE else View.GONE
        v(R.id.btnPresent).visibility = if (maze) View.GONE else View.VISIBLE
        v(R.id.btnChhutti).visibility = if (maze) View.GONE else View.VISIBLE
    }

    private fun markIt(status: String) {
        tv(R.id.homeMsg).text = "⏳ Saving..."
        scope.launch {
            try {
                val r = Api.mark(status)
                tv(R.id.homeMsg).text = "✅ ${r.getString("date")} ka ${r.getString("status")} save!"
                cache.clear(); loadHome(true)
            } catch (e: Exception) {
                tv(R.id.homeMsg).text = "❌ ${e.message}"
            }
        }
    }

    private fun loadCal() {
        if (calY == 0) {
            val c = Calendar.getInstance()
            calY = c.get(Calendar.YEAR); calM = c.get(Calendar.MONTH) + 1
        }
        val names = arrayOf("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")
        tv(R.id.calTitle).text = "${names[calM - 1]} $calY"
        val grid = findViewById<GridLayout>(R.id.calGrid)
        val key = "cal:$calY-$calM"
        if (cache.containsKey(key)) { paintCal(grid, cache[key]!!); return }
        grid.removeAllViews()
        val tvl = TextView(this); tvl.text = "⏳..."; grid.addView(tvl)
        scope.launch {
            try {
                val r = Api.calendar(calY, calM)
                cache[key] = r; paintCal(grid, r)
            } catch (e: Exception) {
                grid.removeAllViews()
                val t = TextView(this@MainActivity); t.text = "❌ ${e.message}"; grid.addView(t)
            }
        }
    }

    private fun paintCal(grid: GridLayout, r: JSONObject) {
        grid.removeAllViews()
        val days = r.getJSONObject("days")
        val cal = Calendar.getInstance()
        cal.set(calY, calM - 1, 1)
        val first = (cal.get(Calendar.DAY_OF_WEEK) - 1) % 7
        repeat(first) { grid.addView(View(this)) }
        val n = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
        for (d in 1..n) {
            val ds = "%02d/%02d/%04d".format(d, calM, calY)
            val marker = days.optJSONObject(ds)?.optString("marker") ?: "none"
            val b = Button(this)
            b.text = d.toString()
            b.setBackgroundColor(
                when (marker) {
                    "present" -> 0xFF166534.toInt()
                    "absent" -> 0xFF991B1B.toInt()
                    "holiday" -> 0xFF854D0E.toInt()
                    "chutti" -> 0xFF9A3412.toInt()
                    else -> 0xFF0F2038.toInt()
                })
            b.setTextColor(Color.WHITE)
            b.setOnClickListener { showDay(ds) }
            grid.addView(b)
        }
    }

    private fun showDay(ds: String) {
        scope.launch {
            try {
                val r = Api.record(ds)
                val st = r.optString("status", "")
                tv(R.id.dayDetail).visibility = View.VISIBLE
                tv(R.id.dayDetail).text = "🗓️ $ds\n" +
                    if (st.isNotEmpty()) "Status: $st" else if (r.optBoolean("holiday")) "🏖️ COLLEGE BAND tha!" else "❓ Koi record nahi"
                v(R.id.btnProof).visibility = if (r.optBoolean("has_proof")) View.VISIBLE else View.GONE
                v(R.id.btnProof).setOnClickListener { loadProof(ds) }
            } catch (e: Exception) {
                tv(R.id.dayDetail).visibility = View.VISIBLE
                tv(R.id.dayDetail).text = "❌ ${e.message}"
            }
        }
    }

    private fun loadProof(ds: String) {
        scope.launch {
            try {
                val (ct, bytes) = Api.proofBytes(ds, true)
                if (ct.contains("image")) {
                    val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    v(R.id.proofImg).visibility = View.VISIBLE
                    findViewById<ImageView>(R.id.proofImg).setImageBitmap(bmp)
                }
            } catch (e: Exception) {
                tv(R.id.dayDetail).text = "❌ ${e.message}"
            }
        }
    }

    private fun loadStats() {
        if (cache.containsKey("stats")) { paintStats(cache["stats"]!!); return }
        tv(R.id.statsPct).text = "⏳..."
        scope.launch {
            try {
                val s = Api.stats()
                cache["stats"] = s; paintStats(s)
            } catch (e: Exception) {
                tv(R.id.statsCards).text = "❌ ${e.message}"
            }
        }
    }

    private fun paintStats(s: JSONObject) {
        tv(R.id.statsPct).text = "${s.getDouble("percent")}%"
        tv(R.id.statsCards).text = "🎒 Khule: ${s.getInt("college_open")}\n" +
            "🔒 Band: ${s.getInt("college_closed")}\n✅ Present: ${s.getInt("present")}\n" +
            "😁 Chhutti: ${s.getInt("chutti")}\n🚫 Absent: ${s.getInt("absent")}"
    }

    private fun sendChat(t: String) {
        val box = tv(R.id.chatBox)
        box.append("\n👤: $t\n")
        scope.launch {
            try {
                val r = Api.chat(t)
                var txt = "\n🤖: ${r.getString("reply")}\n"
                if (r.has("options")) txt += r.getJSONArray("options").let { arr ->
                    (0 until arr.length()).joinToString(" | ") { arr.getString(it) }
                } + "\n"
                box.append(txt)
            } catch (e: Exception) {
                box.append("\n🤖: ❌ ${e.message}\n")
            }
        }
    }

    private fun holidaySubmit(dry: Boolean) {
        scope.launch {
            try {
                val url = Api.base.trimEnd('/') + "/admin/holiday?dry_run=" + dry
                val boundary = "----${System.currentTimeMillis()}"
                val body = StringBuilder()
                fun field(n: String, v: String) {
                    body.append("--$boundary\r\nContent-Disposition: form-data; name=\"$n\"\r\n\r\n$v\r\n")
                }
                field("date", findViewById<EditText>(R.id.inHday).text.toString().trim())
                field("proof_text", findViewById<EditText>(R.id.inHtext).text.toString().trim())
                body.append("--$boundary--\r\n")
                val c = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                c.requestMethod = "POST"
                c.doOutput = true
                c.setRequestProperty("X-Token", Api.token)
                c.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                val txt = (if (c.responseCode in 200..299) c.inputStream else c.errorStream)
                    ?.bufferedReader()?.readText() ?: ""
                c.disconnect()
                val j = JSONObject(txt)
                if (c.responseCode !in 200..299) throw Exception(j.opt("detail").toString())
                tv(R.id.adminMsg).text = if (dry) "👁️ Preview:\n" + j.getString("preview")
                    else "🏖️ Holiday declare! ${j.getString("date")}"
                if (!dry) cache.clear()
            } catch (e: Exception) {
                tv(R.id.adminMsg).text = "❌ ${e.message}"
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
