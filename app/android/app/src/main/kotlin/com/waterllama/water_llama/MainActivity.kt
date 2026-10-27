package com.waterllama.water_llama

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// 点选后暂存的目标别名：延迟到用户离开应用（回到桌面）的瞬间再应用。
    /// 立刻应用会停用正在运行的 LAUNCHER 别名，系统随即结束当前
    /// Activity——用户看到的就是「切个图标 app 却闪退」
    private var pendingIconAlias: String? = null

    /// 音效通道：Dart 侧按 kind 请求播放，原生播放「加水成功」音效
    private var waterPlayer: MediaPlayer? = null

    /// App 图标切换通道：Dart 侧传完整 alias 类名，原生侧暂存，
    /// 在 onUserLeaveHint/onStop 统一应用（停用当前启用的别名、启用目标
    /// 别名，LAUNCHER 唯一入口随之切换）
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.icon.switcher")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val alias = call.argument<String>("alias") ?: ""
                        if (alias.isBlank()) {
                            result.error("ICON_ERROR", "empty alias", null)
                        } else {
                            pendingIconAlias = alias
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 通知设置通道：用户已永久拒绝通知权限时，系统不会再弹权限框，
        // 只能跳本应用的系统通知设置页让用户手动开启
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.notification.settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val ok = try {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            } else {
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:$packageName"),
                                )
                            }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            true
                        } catch (_: Exception) {
                            false
                        }
                        result.success(ok)
                    }
                    else -> result.notImplemented()
                }
            }
        // App 音效通道：目标完成 / 弹弓命中
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waterllama/sound")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        playSound(call.argument<String>("kind") ?: "")
                        result.success(true)
                    }
                    // 试听提醒音效：sound = raw 资源名 / default / none
                    "preview" -> {
                        playPreview(call.argument<String>("sound") ?: "default")
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 播放「加水成功」音效（res/raw/water_add.m4a）
     * 参考竞品喝水提示音的水流感，替代原 ToneGenerator 拨号式提示音；
     * kind 暂不区分（goal / hit / widget 同一音色，goal 由 Dart 侧叠加震动）
     */
    private fun playSound(kind: String) {
        try {
            waterPlayer?.release()
            val mp = MediaPlayer.create(this, R.raw.water_add) ?: return
            waterPlayer = mp
            mp.setVolume(0.9f, 0.9f)
            mp.setOnCompletionListener {
                try {
                    it.release()
                } catch (_: Exception) {
                }
                if (waterPlayer === it) waterPlayer = null
            }
            mp.start()
        } catch (_: Exception) {
            // 音频设备不可用时静默，不影响主流程
        }
    }

    /**
     * 试听提醒音效：
     * - none   静音，不播放
     * - default 系统默认通知音
     * - 其余    res/raw 下同名资源（reminder_chime / reminder_drop / reminder_soft）
     */
    private fun playPreview(soundKey: String) {
        try {
            if (soundKey == "none") return
            if (soundKey == "default") {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                RingtoneManager.getRingtone(this, uri)?.play()
                return
            }
            val resId = resources.getIdentifier(soundKey, "raw", packageName)
            if (resId == 0) return
            waterPlayer?.release()
            val mp = MediaPlayer.create(this, resId) ?: return
            waterPlayer = mp
            mp.setVolume(0.9f, 0.9f)
            mp.setOnCompletionListener {
                try {
                    it.release()
                } catch (_: Exception) {
                }
                if (waterPlayer === it) waterPlayer = null
            }
            mp.start()
        } catch (_: Exception) {
            // 音频设备不可用时静默
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // 自愈：重装/系统重置后默认别名会跟随清单重新启用，桌面上会出现
        // 两个「喝水养成」。启动时按已保存的选择重新收敛（无保存则不动）
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val saved = prefs.getString("flutter.app_icon_selection", null)
            if (!saved.isNullOrBlank()) {
                val ok = switchIcon("com.waterllama.water_llama.AppIcon_$saved")
                if (!ok) {
                    // 保存的选择对应的别名已被从清单移除：清掉记录并回到
                    // 默认图标，避免永远指向不存在的入口
                    prefs.edit().remove("flutter.app_icon_selection").apply()
                    switchIcon("com.waterllama.water_llama.AppIcon_char_alpaca_0")
                }
            }
        } catch (_: Exception) {
            // 自愈失败不影响启动
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // 用户主动离开（回桌面/进多任务）的瞬间生效，回到桌面即可见
        applyPendingIcon()
    }

    override fun onStop() {
        // 兜底：下拉通知栏/锁屏/跳其他应用等非 onUserLeaveHint 的离开路径
        applyPendingIcon()
        super.onStop()
    }

    override fun onDestroy() {
        try {
            waterPlayer?.release()
        } catch (_: Exception) {
        }
        waterPlayer = null
        super.onDestroy()
    }

    private fun applyPendingIcon() {
        val target = pendingIconAlias ?: return
        pendingIconAlias = null
        try {
            switchIcon(target)
        } catch (_: Exception) {
            // 生效失败不崩溃；下次启动 onCreate 自愈收敛
        }
    }

    /** 全部 LAUNCHER 别名 id（与 Manifest 保持同步，增删图标须同步此表）。
     *  vivo ROM 的 GET_ACTIVITIES 返回数组不含 activity-alias，依赖系统
     *  返回遍历停用从未生效过（多个别名同时处于启用态）；此后加的存在
     *  性守卫更因此恒判失败，切图标完全不生效——改为内置清单直连启停 */
    private val allIconAliases: List<String> by lazy {
        val chars = listOf("alpaca", "sheep", "rabbit", "fox", "corgi",
            "orange_cat", "sleepy_cat", "silly_dog", "poodle")
        val list = mutableListOf("AppIcon_default")
        for (c in chars) for (j in 0..5) list.add("AppIcon_char_${c}_$j")
        list.addAll(listOf(
            "AppIcon_glyph2_drop0", "AppIcon_glyph2_drop1",
            "AppIcon_glyph2_drop4", "AppIcon_glyph2_drop5",
            "AppIcon_glyph2_drop6",
        ))
        list
    }

    private fun switchIcon(targetAlias: String): Boolean {
        val fullTarget = if (targetAlias.startsWith(".")) packageName + targetAlias else targetAlias
        val pm = packageManager
        // 先启用目标。不存在/非法的别名交给 PackageManager 报错兜底：
        // 自愈逻辑据此识别「保存的选择已从清单移除」并回退默认图标
        val enabled = try {
            pm.setComponentEnabledSetting(
                ComponentName(packageName, fullTarget),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            true
        } catch (_: IllegalArgumentException) {
            false
        } catch (_: SecurityException) {
            false
        }
        if (!enabled) return false
        // 停用目标以外的一切别名（含默认入口），保证 LAUNCHER 唯一；
        // 显式 DISABLED 的跳过，每次启动只发必要的 PACKAGE_CHANGED
        for (alias in allIconAliases) {
            val name = "$packageName.$alias"
            if (name == fullTarget) continue
            val cn = ComponentName(packageName, name)
            try {
                if (pm.getComponentEnabledSetting(cn) !=
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED) {
                    pm.setComponentEnabledSetting(
                        cn,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                }
            } catch (_: Exception) {
                // 别名已从清单移除等情形，忽略
            }
        }
        return true
    }
}
