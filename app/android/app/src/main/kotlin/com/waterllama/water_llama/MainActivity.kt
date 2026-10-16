package com.waterllama.water_llama

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// App 图标切换通道：Dart 侧传完整 alias 类名，
    /// 原生侧停用当前启用的别名、启用目标别名（LAUNCHER 唯一入口随之切换）
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.icon.switcher")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val alias = call.argument<String>("alias") ?: ""
                        try {
                            switchIcon(alias)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ICON_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // 自愈：重装/系统重置后默认别名会跟随清单重新启用，桌面上会出现
        // 两个「喝水养成」。启动时按已保存的选择重新收敛（无保存则不动）
        try {
            val saved = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.app_icon_selection", null)
            if (!saved.isNullOrBlank()) {
                switchIcon("com.waterllama.water_llama.AppIcon_$saved")
            }
        } catch (_: Exception) {
            // 自愈失败不影响启动
        }
    }

    private fun switchIcon(targetAlias: String) {
        val fullTarget = if (targetAlias.startsWith(".")) packageName + targetAlias else targetAlias
        val pm = packageManager
        val pkg = pm.getPackageInfo(packageName, PackageManager.GET_ACTIVITIES)
        val activities = pkg.activities ?: return
        for (info in activities) {
            if (!info.name.startsWith("$packageName.AppIcon")) continue
            if (info.name == fullTarget) continue
            val state = pm.getComponentEnabledSetting(ComponentName(packageName, info.name))
            // 注意：manifest 里 enabled=true/false 的别名查出来是 DEFAULT（跟随清单）。
            // 默认别名从未被显式 set 过（状态 DEFAULT 而实际是启用）——只停用
            // ENABLED 会导致它一直显示，桌面出现双图标。这里对一切「非目标的
            // 且未处于显式 DISABLED」的别名统一显式停用
            if (state != PackageManager.COMPONENT_ENABLED_STATE_DISABLED) {
                pm.setComponentEnabledSetting(
                    ComponentName(packageName, info.name),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
        }
        pm.setComponentEnabledSetting(
            ComponentName(packageName, fullTarget),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
