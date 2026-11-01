#!/bin/bash
set -e
cd "$(dirname "$0")"
P=proj
J=$P/app/src/main/java/com/pablom/teleprompter
mkdir -p $J $P/app/src/main/res/drawable

cat > $P/settings.gradle.kts <<'__EOF__'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "teleprompter"
include(":app")
__EOF__

cat > $P/build.gradle.kts <<'__EOF__'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
__EOF__

cat > $P/gradle.properties <<'__EOF__'
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
android.useAndroidX=false
android.nonTransitiveRClass=true
kotlin.code.style=official
__EOF__

cat > $P/app/build.gradle.kts <<'__EOF__'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.pablom.teleprompter"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.pablom.teleprompter"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
}
__EOF__

cat > $P/app/src/main/AndroidManifest.xml <<'__EOF__'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <queries>
        <package android:name="com.sec.android.app.camera" />
    </queries>
    <application
        android:allowBackup="false"
        android:icon="@drawable/ic_launcher"
        android:label="Teleprompter"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service
            android:name=".OverlayService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="teleprompter_overlay" />
        </service>
    </application>
</manifest>
__EOF__

cat > $P/app/src/main/res/drawable/ic_launcher.xml <<'__EOF__'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#141414"
        android:pathData="M0,0h108v108h-108z" />
    <path
        android:fillColor="#B83A2A"
        android:pathData="M54,16m-8,0a8,8 0,1 1,16 0a8,8 0,1 1,-16 0" />
    <path
        android:fillColor="#F0E6C8"
        android:pathData="M24,40h60v8h-60z M32,56h44v8h-44z M28,72h52v8h-52z" />
</vector>
__EOF__

cat > $J/Script.kt <<'__EOF__'
package com.pablom.teleprompter

class Tramo(var n: Int, var name: String, var text: String)

private class Tmp(val n: Int, val name: String) {
    val raw = ArrayList<String>()
}

object ScriptParser {
    private val HEAD = Regex("""^\s*(?:#{1,6}\s*)?(?:\*\*|__)?\s*(?:tramo|bloque|parte|segmento)\s*(\d+)\s*(?:\*\*|__)?\s*[:.\-–—]*\s*(.*)$""", RegexOption.IGNORE_CASE)
    private val STOPH = Regex("""^\s*(?:#{1,6}\s*)?(?:\*\*|__)?\s*(?:fuentes?|notas?|referencias|bibliograf[ií]a|indicaciones)\s*:?\s*(?:\*\*|__)?\s*$""", RegexOption.IGNORE_CASE)
    private val MDHEAD = Regex("""^\s*#{1,6}\s""")
    private val NOTEPFX = Regex("""^(?:nota|notas|fuente|fuentes|indicaci[oó]n|acotaci[oó]n|en pantalla|texto en pantalla|placa|cartel)\s*:""", RegexOption.IGNORE_CASE)
    private val RULE = Regex("""^(?:[-*_=]\s*){3,}$""")
    private val BRACKET = Regex("""\[[^\]]{0,300}\](?!\()""")
    private val COMMENT = Regex("""<!--[\s\S]*?-->""")
    private val SENT_END = Regex("""[.!?…:;»")”]$""")
    private val LINK = Regex("""\[([^\]]*)\]\([^)]*\)""")
    private val BULLET = Regex("""^\s*[-*•]\s+""")
    private val NUMBERED = Regex("""^\s*\d+[.)]\s+""")
    private val MARKS = Regex("(\\*\\*|__|\\*|\\u0060)")
    private val UNDER = Regex("""(^|\s)_([^_]+)_(?=\s|$|[.,;:!?])""")
    private val PIPE = Regex("""\s*\|\s*""")
    private val NAMEPFX = Regex("""^[\s\-–—:·•]+""")
    private val MANYNL = Regex("""\n{3,}""")
    private val WS = Regex("""\s+""")

    fun words(t: String): Int = t.split(WS).filter { it.isNotEmpty() }.size

    private fun cleanInline(l: String): String {
        var s = l
        s = LINK.replace(s, "$1")
        s = BULLET.replace(s, "")
        s = NUMBERED.replace(s, "")
        s = MARKS.replace(s, "")
        s = UNDER.replace(s, "$1$2")
        s = PIPE.replace(s, "\n")
        return s
    }

    private fun cleanBlock(t0: String, isPdf: Boolean): String {
        val t = COMMENT.replace(t0, "")
        val out = ArrayList<String>()
        for (rawLine in t.split("\n")) {
            var l = rawLine.trim()
            if (l.isNotEmpty()) {
                val l2 = BRACKET.replace(l, "").trim()
                if (l2.isEmpty()) continue
                l = l2
            }
            if (l.startsWith(">")) continue
            if (RULE.matches(l)) continue
            if (NOTEPFX.containsMatchIn(l.trimStart('*', '_', ' '))) continue
            out.add(if (l.isEmpty()) "" else cleanInline(l).trim())
        }
        var lines: List<String> = out
        if (isPdf) {
            val j = ArrayList<String>()
            for (l in lines) {
                val lastIdx = j.size - 1
                if (l.isNotEmpty() && lastIdx >= 0 && j[lastIdx].isNotEmpty() && !SENT_END.containsMatchIn(j[lastIdx])) {
                    j[lastIdx] = j[lastIdx] + " " + l
                } else {
                    j.add(l)
                }
            }
            lines = j
        }
        return MANYNL.replace(lines.joinToString("\n"), "\n\n").trim()
    }

    fun parse(raw: String, isPdf: Boolean): List<Tramo> {
        val lines = raw.replace("\r", "").split("\n")
        val tr = ArrayList<Tmp>()
        var cur: Tmp? = null
        for (ln in lines) {
            val m = if (ln.length < 140) HEAD.find(ln) else null
            if (m != null) {
                val name = NAMEPFX.replace(cleanInline(m.groupValues[2]), "").trim()
                val created = Tmp(m.groupValues[1].toInt(), name)
                tr.add(created)
                cur = created
                continue
            }
            val c = cur ?: continue
            if (MDHEAD.containsMatchIn(ln) || STOPH.containsMatchIn(ln)) {
                cur = null
                continue
            }
            c.raw.add(ln)
        }
        if (tr.isEmpty()) {
            val all = Tmp(1, "Guion completo")
            for (ln in lines) {
                if (!MDHEAD.containsMatchIn(ln)) all.raw.add(ln)
            }
            tr.add(all)
        }
        val result = ArrayList<Tramo>()
        for (t in tr) {
            val text = cleanBlock(t.raw.joinToString("\n"), isPdf)
            if (text.isNotEmpty()) result.add(Tramo(t.n, t.name, text))
        }
        return result
    }
}
__EOF__

cat > $J/PdfText.kt <<'__EOF__'
package com.pablom.teleprompter

import android.content.Context
import android.net.Uri
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper

object PdfText {
    private fun edge(a: List<String>): List<String> {
        val ne = a.filter { it.isNotEmpty() }
        return ne.take(2) + ne.takeLast(2)
    }

    fun extract(ctx: Context, uri: Uri): String {
        PDFBoxResourceLoader.init(ctx.applicationContext)
        val ins = ctx.contentResolver.openInputStream(uri) ?: throw IllegalStateException("No pude abrir el PDF")
        val pages = ArrayList<MutableList<String>>()
        val doc = PDDocument.load(ins)
        try {
            val st = PDFTextStripper()
            st.setSortByPosition(true)
            val total = doc.getNumberOfPages()
            for (p in 1..total) {
                st.setStartPage(p)
                st.setEndPage(p)
                val txt = st.getText(doc).replace("\r", "")
                pages.add(txt.split("\n").map { it.trim() }.toMutableList())
            }
        } finally {
            doc.close()
            ins.close()
        }
        if (pages.size > 1) {
            val cnt = HashMap<String, Int>()
            for (a in pages) {
                for (x in edge(a).toSet()) cnt[x] = (cnt[x] ?: 0) + 1
            }
            for (i in pages.indices) {
                val e = edge(pages[i]).toSet()
                pages[i] = pages[i].filter { !(e.contains(it) && (cnt[it] ?: 0) >= 2 && it.length < 90) }.toMutableList()
            }
        }
        val pn = Regex("""^\s*(?:p[áa]g(?:ina)?\.?\s*)?\d+(?:\s*(?:/|de)\s*\d+)?\s*$""", RegexOption.IGNORE_CASE)
        return pages.joinToString("\n") { a -> a.filter { !pn.matches(it) }.joinToString("\n") }
    }
}
__EOF__

cat > $J/TpState.kt <<'__EOF__'
package com.pablom.teleprompter

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color

object TpState {
    private var prefs: SharedPreferences? = null
    val tramos = ArrayList<Tramo>()
    var tema: String = ""

    fun init(ctx: Context) {
        if (prefs == null) {
            prefs = ctx.applicationContext.getSharedPreferences("tp", Context.MODE_PRIVATE)
            load()
        }
    }

    private fun p(): SharedPreferences = prefs!!

    var fs: Float
        get() = p().getFloat("fs", 9f)
        set(v) { p().edit().putFloat("fs", v).apply() }
    var w: Int
        get() = p().getInt("w", 70)
        set(v) { p().edit().putInt("w", v).apply() }
    var top: Int
        get() = p().getInt("top", 3)
        set(v) { p().edit().putInt("top", v).apply() }
    var color: Int
        get() = p().getInt("color", Color.WHITE)
        set(v) { p().edit().putInt("color", v).apply() }
    var outline: Boolean
        get() = p().getBoolean("outline", true)
        set(v) { p().edit().putBoolean("outline", v).apply() }
    var count: Int
        get() = p().getInt("count", 5)
        set(v) { p().edit().putInt("count", v).apply() }
    var speed: Float
        get() = p().getFloat("speed", 1f)
        set(v) { p().edit().putFloat("speed", v).apply() }

    fun save() {
        val sb = StringBuilder()
        for (t in tramos) {
            sb.append(t.n).append('\u0001').append(t.name).append('\u0001').append(t.text).append('\u0002')
        }
        p().edit().putString("script", sb.toString()).putString("tema", tema).apply()
    }

    private fun load() {
        tramos.clear()
        val s = p().getString("script", "") ?: ""
        if (s.isNotEmpty()) {
            for (rec in s.split('\u0002')) {
                if (rec.isEmpty()) continue
                val f = rec.split('\u0001')
                if (f.size >= 3) tramos.add(Tramo(f[0].toIntOrNull() ?: 1, f[1], f[2]))
            }
        }
        tema = p().getString("tema", "") ?: ""
    }
}
__EOF__

cat > $J/TeleView.kt <<'__EOF__'
package com.pablom.teleprompter

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.View
import kotlin.math.max

class TeleView(ctx: Context) : View(ctx) {
    var pos = 0f
    var countText = ""
    var maxPos = 0f
    var textHeight = 1f

    private var lineH = 0f
    private var topPx = 0f
    private var colW = 0f
    private var outline = true
    private var fillL: StaticLayout? = null
    private var strokeL: StaticLayout? = null
    private val fillP = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val strokeP = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val markP = Paint(Paint.ANTI_ALIAS_FLAG)
    private val countP = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val markPath = Path()

    fun configure(text: String) {
        val dm = resources.displayMetrics
        val sw = dm.widthPixels.toFloat()
        val fontPx = sw * TpState.fs / 100f
        colW = sw * TpState.w / 100f
        topPx = dm.heightPixels * TpState.top / 100f
        outline = TpState.outline

        fillP.textSize = fontPx
        fillP.typeface = Typeface.DEFAULT_BOLD
        fillP.color = TpState.color
        strokeP.textSize = fontPx
        strokeP.typeface = Typeface.DEFAULT_BOLD
        strokeP.style = Paint.Style.STROKE
        strokeP.strokeWidth = fontPx * 0.16f
        strokeP.strokeJoin = Paint.Join.ROUND
        strokeP.color = if (TpState.color == Color.BLACK) Color.WHITE else Color.BLACK

        val w = colW.toInt()
        val f = build(text, fillP, w)
        fillL = f
        strokeL = build(text, strokeP, w)
        textHeight = max(1f, f.height.toFloat())
        lineH = if (f.lineCount > 0) (f.getLineBottom(0) - f.getLineTop(0)).toFloat() else fontPx
        maxPos = max(0f, textHeight - lineH)

        val d = dm.density
        val my = topPx + lineH / 2f
        markPath.reset()
        markPath.moveTo(0f, my - 12f * d)
        markPath.lineTo(16f * d, my)
        markPath.lineTo(0f, my + 12f * d)
        markPath.close()
        markP.color = Color.parseColor("#B83A2A")
        markP.style = Paint.Style.FILL

        countP.color = Color.WHITE
        countP.typeface = Typeface.DEFAULT_BOLD
        countP.textAlign = Paint.Align.CENTER
        countP.setShadowLayer(24f, 0f, 0f, Color.BLACK)
        invalidate()
    }

    private fun build(text: String, p: TextPaint, w: Int): StaticLayout {
        return StaticLayout.Builder.obtain(text, 0, text.length, p, w)
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .setLineSpacing(0f, 1.15f)
            .setIncludePad(false)
            .build()
    }

    override fun onDraw(c: Canvas) {
        val fl = fillL ?: return
        val x = (width - colW) / 2f
        c.save()
        c.translate(x, topPx - pos)
        if (outline) strokeL?.draw(c)
        fl.draw(c)
        c.restore()
        c.drawPath(markPath, markP)
        if (countText.isNotEmpty()) {
            countP.textSize = width * 0.35f
            c.drawText(countText, width / 2f, height / 2f + countP.textSize / 3f, countP)
        }
    }
}
__EOF__

cat > $J/OverlayService.kt <<'__EOF__'
package com.pablom.teleprompter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlin.math.max

class OverlayService : Service() {
    private var wm: WindowManager? = null
    private var tele: TeleView? = null
    private var panel: LinearLayout? = null
    private var pl: WindowManager.LayoutParams? = null
    private var playBtn: TextView? = null
    private var speedLbl: TextView? = null
    private var tramoLbl: TextView? = null
    private var cur = 0
    private var pos = 0f
    private var words = 1
    private var playing = false
    private var countdown = 0f
    private var last = 0L
    private var dx0 = 0f
    private var dy0 = 0f
    private var px0 = 0
    private var py0 = 0

    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            var dt = if (last == 0L) 0f else (frameTimeNanos - last) / 1000000000f
            if (dt > 0.1f) dt = 0.1f
            last = frameTimeNanos
            val v = tele
            if (v != null) {
                var dirty = false
                if (countdown > 0f) {
                    countdown -= dt
                    if (countdown <= 0f) {
                        countdown = 0f
                        v.countText = ""
                        playing = true
                        refreshPlay()
                    } else {
                        v.countText = Math.ceil(countdown.toDouble()).toInt().toString()
                    }
                    dirty = true
                } else if (playing) {
                    pos += pxps() * dt
                    if (pos >= v.maxPos) {
                        pos = v.maxPos
                        playing = false
                        refreshPlay()
                    }
                    dirty = true
                }
                if (dirty) {
                    v.pos = pos
                    v.invalidate()
                }
            }
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        TpState.init(this)
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            startFg()
            buildTele()
            buildPanel()
            loadTramo(0)
            Choreographer.getInstance().postFrameCallback(frame)
        } catch (e: Exception) {
            Toast.makeText(this, "No pude mostrar el teleprompter: " + e.message, Toast.LENGTH_LONG).show()
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null && intent.action == "STOP") {
            stopSelf()
            return START_NOT_STICKY
        }
        if (tele != null) loadTramo(0)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Choreographer.getInstance().removeFrameCallback(frame)
        val m = wm
        if (m != null) {
            try { tele?.let { m.removeView(it) } } catch (e: Exception) {}
            try { panel?.let { m.removeView(it) } } catch (e: Exception) {}
        }
        super.onDestroy()
    }

    private fun startFg() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("tp", "Teleprompter", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 0, Intent(this, OverlayService::class.java).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(this, "tp")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Teleprompter activo")
            .setContentText("Tocá Cerrar para sacarlo de la pantalla")
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel), "Cerrar", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, n)
        }
    }

    private fun buildTele() {
        val v = TeleView(this)
        tele = v
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.TOP or Gravity.START
        if (Build.VERSION.SDK_INT >= 28) {
            lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        wm?.addView(v, lp)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun bg(color: Int, r: Int): GradientDrawable {
        val g = GradientDrawable()
        g.setColor(color)
        g.cornerRadius = dp(r).toFloat()
        return g
    }

    private fun btn(label: String, h: Int, size: Float, onClick: () -> Unit): TextView {
        val t = TextView(this)
        t.text = label
        t.setTextColor(Color.WHITE)
        t.textSize = size
        t.gravity = Gravity.CENTER
        t.background = bg(Color.argb(85, 255, 255, 255), 10)
        val lp = LinearLayout.LayoutParams(dp(54), dp(h))
        lp.topMargin = dp(4)
        t.layoutParams = lp
        t.setOnClickListener { onClick() }
        return t
    }

    private fun lbl(size: Float): TextView {
        val t = TextView(this)
        t.setTextColor(Color.WHITE)
        t.textSize = size
        t.gravity = Gravity.CENTER
        t.layoutParams = LinearLayout.LayoutParams(dp(54), dp(24))
        return t
    }

    private fun buildPanel() {
        val p = LinearLayout(this)
        p.orientation = LinearLayout.VERTICAL
        p.setPadding(dp(6), dp(6), dp(6), dp(6))
        p.background = bg(Color.argb(150, 0, 0, 0), 16)
        panel = p

        val grip = TextView(this)
        grip.text = "::::"
        grip.setTextColor(Color.WHITE)
        grip.textSize = 16f
        grip.gravity = Gravity.CENTER
        grip.layoutParams = LinearLayout.LayoutParams(dp(54), dp(30))
        p.addView(grip)

        val pb = btn("▶", 52, 24f) { togglePlay() }
        playBtn = pb
        p.addView(pb)
        p.addView(btn("+", 40, 22f) { setSpeed(0.1f) })
        val sl = lbl(13f)
        speedLbl = sl
        p.addView(sl)
        p.addView(btn("−", 40, 22f) { setSpeed(-0.1f) })
        p.addView(btn("↺", 40, 22f) { loadTramo(cur) })
        p.addView(btn("‹", 40, 24f) { loadTramo(cur - 1) })
        val tl = lbl(12f)
        tramoLbl = tl
        p.addView(tl)
        p.addView(btn("›", 40, 24f) { loadTramo(cur + 1) })
        p.addView(btn("✕", 40, 18f) { stopSelf() })

        val dm = resources.displayMetrics
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.TOP or Gravity.START
        lp.x = dm.widthPixels - dp(70)
        lp.y = (dm.heightPixels * 0.22f).toInt()
        pl = lp

        grip.setOnTouchListener { _, e ->
            val q = pl
            if (q != null) {
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> {
                        dx0 = e.rawX
                        dy0 = e.rawY
                        px0 = q.x
                        py0 = q.y
                    }
                    MotionEvent.ACTION_MOVE -> {
                        q.x = px0 + (e.rawX - dx0).toInt()
                        q.y = py0 + (e.rawY - dy0).toInt()
                        wm?.updateViewLayout(p, q)
                    }
                }
            }
            true
        }
        wm?.addView(p, lp)
    }

    private fun refreshPlay() {
        playBtn?.text = if (playing || countdown > 0f) "⏸" else "▶"
    }

    private fun refreshLabels() {
        speedLbl?.text = String.format("%.1fx", TpState.speed)
        val n = TpState.tramos.size
        tramoLbl?.text = if (n == 0) "-" else "T" + TpState.tramos[cur].n + " " + (cur + 1) + "/" + n
    }

    private fun pxps(): Float {
        val v = tele ?: return 0f
        return 150f / 60f * (v.textHeight / words) * TpState.speed
    }

    private fun setSpeed(d: Float) {
        var s = Math.round((TpState.speed + d) * 10f) / 10f
        if (s < 0.5f) s = 0.5f
        if (s > 3f) s = 3f
        TpState.speed = s
        refreshLabels()
    }

    private fun togglePlay() {
        val v = tele ?: return
        if (countdown > 0f) {
            countdown = 0f
            v.countText = ""
            v.invalidate()
            refreshPlay()
            return
        }
        if (playing) {
            playing = false
        } else {
            if (pos >= v.maxPos - 1f) {
                pos = 0f
                v.pos = 0f
            }
            if (TpState.count > 0) {
                countdown = TpState.count.toFloat()
                v.countText = TpState.count.toString()
            } else {
                playing = true
            }
        }
        refreshPlay()
        v.invalidate()
    }

    private fun loadTramo(i: Int) {
        val v = tele ?: return
        val list = TpState.tramos
        playing = false
        countdown = 0f
        pos = 0f
        v.countText = ""
        if (list.isEmpty()) {
            cur = 0
            words = 1
            v.configure("Primero cargá un guion en la app Teleprompter")
        } else {
            cur = i
            if (cur < 0) cur = 0
            if (cur > list.size - 1) cur = list.size - 1
            val t = list[cur]
            words = max(1, ScriptParser.words(t.text))
            v.configure(t.text)
        }
        v.pos = 0f
        v.invalidate()
        refreshPlay()
        refreshLabels()
    }
}
__EOF__

cat > $J/MainActivity.kt <<'__EOF__'
package com.pablom.teleprompter

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var temaEt: EditText
    private lateinit var box: LinearLayout
    private val colors = intArrayOf(Color.WHITE, Color.parseColor("#FFE600"), Color.parseColor("#3DDC50"), Color.BLACK, Color.parseColor("#FF2A2A"))
    private val colorNames = arrayOf("Blanco", "Amarillo", "Verde", "Negro", "Rojo")
    private val colorBtns = ArrayList<TextView>()

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun label(text: String, size: Float, color: Int): TextView {
        val t = TextView(this)
        t.text = text
        t.textSize = size
        t.setTextColor(color)
        t.setPadding(0, dp(8), 0, dp(4))
        return t
    }

    private fun button(text: String, color: String, onClick: () -> Unit): Button {
        val b = Button(this)
        b.text = text
        b.setTextColor(Color.WHITE)
        b.setBackgroundColor(Color.parseColor(color))
        val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(52))
        lp.topMargin = dp(10)
        b.layoutParams = lp
        b.setOnClickListener { onClick() }
        return b
    }

    private fun toast(m: String) {
        Toast.makeText(this, m, Toast.LENGTH_LONG).show()
    }

    private fun addSeek(parent: LinearLayout, title: String, max: Int, start: Int, fmt: (Int) -> String, onChange: (Int) -> Unit) {
        val tv = label(title + ": " + fmt(start), 14f, Color.parseColor("#CCCCCC"))
        val sb = SeekBar(this)
        sb.max = max
        sb.progress = start
        sb.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?, p: Int, u: Boolean) {
                tv.text = title + ": " + fmt(p)
                onChange(p)
            }
            override fun onStartTrackingTouch(s: SeekBar?) {}
            override fun onStopTrackingTouch(s: SeekBar?) {}
        })
        parent.addView(tv)
        parent.addView(sb)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        TpState.init(this)
        val sv = ScrollView(this)
        sv.setBackgroundColor(Color.parseColor("#141414"))
        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(16), dp(24), dp(16), dp(40))
        sv.addView(root)

        root.addView(label("Teleprompter", 26f, Color.WHITE))
        root.addView(label("Cargá el guion con tramos marcados como TRAMO 1, TRAMO 2...", 14f, Color.parseColor("#AAAAAA")))
        root.addView(button("Elegir guion (.md, .txt o PDF)", "#B83A2A") { pick() })

        root.addView(label("Tema (para nombrar las tomas)", 13f, Color.parseColor("#AAAAAA")))
        temaEt = EditText(this)
        temaEt.setTextColor(Color.WHITE)
        temaEt.setText(TpState.tema)
        temaEt.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(s: Editable?) { TpState.tema = s.toString() }
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
        })
        root.addView(temaEt)

        status = label("", 14f, Color.parseColor("#AAAAAA"))
        root.addView(status)
        box = LinearLayout(this)
        box.orientation = LinearLayout.VERTICAL
        root.addView(box)

        root.addView(label("Ajustes del texto", 20f, Color.WHITE))
        addSeek(root, "Tamaño de letra", 22, ((TpState.fs - 5f) * 2f).toInt(), { p -> (5f + p * 0.5f).toString() }) { p -> TpState.fs = 5f + p * 0.5f }
        addSeek(root, "Ancho del texto (%)", 12, (TpState.w - 40) / 5, { p -> (40 + p * 5).toString() }) { p -> TpState.w = 40 + p * 5 }
        addSeek(root, "Altura de lectura (% desde arriba)", 40, TpState.top, { p -> p.toString() }) { p -> TpState.top = p }
        addSeek(root, "Cuenta regresiva (segundos)", 15, TpState.count, { p -> p.toString() }) { p -> TpState.count = p }

        root.addView(label("Color de letra", 14f, Color.parseColor("#CCCCCC")))
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        for (i in colors.indices) {
            val c = TextView(this)
            c.gravity = Gravity.CENTER
            c.textSize = 18f
            c.setBackgroundColor(colors[i])
            c.contentDescription = colorNames[i]
            val lp = LinearLayout.LayoutParams(dp(52), dp(52))
            lp.rightMargin = dp(8)
            c.layoutParams = lp
            c.setOnClickListener {
                TpState.color = colors[i]
                refreshColors()
            }
            colorBtns.add(c)
            row.addView(c)
        }
        root.addView(row)
        refreshColors()

        val cb = CheckBox(this)
        cb.text = "Contorno para que se lea sobre el video"
        cb.setTextColor(Color.WHITE)
        cb.isChecked = TpState.outline
        cb.setOnCheckedChangeListener { _, v -> TpState.outline = v }
        root.addView(cb)

        root.addView(button("Mostrar teleprompter", "#B83A2A") { startOverlay() })
        root.addView(button("Abrir cámara de Samsung", "#2A2A2A") { openCamera() })
        root.addView(button("Cerrar teleprompter", "#2A2A2A") { stopService(Intent(this, OverlayService::class.java)) })

        setContentView(sv)
        render()
    }

    private fun refreshColors() {
        for (i in colorBtns.indices) {
            val sel = TpState.color == colors[i]
            colorBtns[i].text = if (sel) "✓" else ""
            colorBtns[i].setTextColor(if (colors[i] == Color.BLACK || colors[i] == Color.parseColor("#FF2A2A")) Color.WHITE else Color.BLACK)
        }
    }

    private fun render() {
        box.removeAllViews()
        val list = TpState.tramos
        status.text = if (list.isEmpty()) "Todavía no cargaste ningún guion." else "Se encontraron " + list.size + " tramo(s). Podés corregir el texto de cada uno."
        for (t in list) {
            val title = "Tramo " + t.n + (if (t.name.isNotEmpty()) " · " + t.name else "") + " · " + ScriptParser.words(t.text) + " palabras"
            box.addView(label(title, 15f, Color.WHITE))
            val et = EditText(this)
            et.setText(t.text)
            et.setTextColor(Color.WHITE)
            et.setBackgroundColor(Color.parseColor("#1E1E1E"))
            et.minLines = 3
            et.gravity = Gravity.TOP
            et.setPadding(dp(10), dp(10), dp(10), dp(10))
            et.addTextChangedListener(object : TextWatcher {
                override fun afterTextChanged(s: Editable?) { t.text = s.toString() }
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            })
            box.addView(et)
        }
    }

    private fun pick() {
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT)
        i.addCategory(Intent.CATEGORY_OPENABLE)
        i.type = "*/*"
        i.putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/markdown", "text/plain", "application/pdf", "text/x-markdown", "application/octet-stream"))
        startActivityForResult(i, 1)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1 || resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        status.text = "Leyendo..."
        Thread {
            try {
                var name = "guion"
                contentResolver.query(uri, null, null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val ix = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (ix >= 0) name = c.getString(ix)
                    }
                }
                val isPdf = name.lowercase().endsWith(".pdf") || contentResolver.getType(uri) == "application/pdf"
                val raw = if (isPdf) {
                    PdfText.extract(this, uri)
                } else {
                    contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) } ?: ""
                }
                val list = ScriptParser.parse(raw, isPdf)
                val fileName = name
                runOnUiThread {
                    TpState.tramos.clear()
                    TpState.tramos.addAll(list)
                    if (temaEt.text.isNullOrEmpty()) {
                        val t = fileName.replace(Regex("""\.[^.]+$"""), "").replace(Regex("^guion[_\\s-]*", RegexOption.IGNORE_CASE), "").replace("_", " ").trim()
                        temaEt.setText(t)
                        TpState.tema = t
                    }
                    TpState.save()
                    render()
                }
            } catch (e: Exception) {
                runOnUiThread { status.text = "Error: " + e.message }
            }
        }.start()
    }

    private fun startOverlay() {
        if (TpState.tramos.isEmpty()) {
            toast("Primero cargá un guion")
            return
        }
        if (!Settings.canDrawOverlays(this)) {
            toast("Activá Mostrar sobre otras apps para Teleprompter y volvé a tocar este botón")
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + packageName)))
            return
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2)
        }
        TpState.save()
        startForegroundService(Intent(this, OverlayService::class.java))
        toast("Teleprompter activo. Ahora abrí la cámara.")
    }

    private fun openCamera() {
        val i = packageManager.getLaunchIntentForPackage("com.sec.android.app.camera")
        if (i != null) startActivity(i) else toast("No encontré la cámara de Samsung")
    }
}
__EOF__

echo "Proyecto generado en $P"
