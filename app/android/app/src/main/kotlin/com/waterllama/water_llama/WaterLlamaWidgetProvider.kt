package com.waterllama.water_llama

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * home_widget 的存储经 MethodChannel 写入：Dart 侧无符号 32 位 ARGB
 * （如 0xFF4DB8D8 = 4291534080 > Int.MAX_VALUE）会被 Android 端存为
 * Long，直接 getInt 强转即 ClassCastException 崩溃。统一按 Number
 * 读取再收窄，兼容历史 Long 数据与新写入的 Integer
 */
private fun SharedPreferences.readIntSafe(key: String, def: Int): Int {
    val raw = try { all[key] } catch (_: Exception) { null } ?: return def
    return (raw as? Number)?.toInt() ?: def
}

/** 喝水养成桌面小组件 Provider（基于 home_widget 插件的 HomeWidgetProvider）
 *
 * 视图对标 App 内「小组件」设置页预览卡：
 * 左上目标容量+百分比 / 右侧角色插画 / 左下连续徽章圆 / 右列饮料格（含饮品图标） */
class WaterLlamaWidgetProvider : HomeWidgetProvider() {

    /** 系统更新小组件时回调：逐实例刷新（桌面可能摆放多个实例） */
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(appWidgetId, buildRemoteViews(context, widgetData))
        }
    }

    /** 按上限降采样解码 PNG（inSampleSize 2 的幂）：帧位图总量受
     *  RemoteViews ~15.5MB 硬限，原分辨率解码 16 帧必崩 */
    private fun decodeCapped(path: String, maxPx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > maxPx) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeFile(path, opts)
    }

    /** 组装小组件视图：读取 Dart 侧写入的共享数据 → 填充文案/颜色/饮品图标。
     *  唯一固定样式（对标竞品「柠檬喝水」：所有设备/所有厂商只此一种，
     *  不可更改）= 全宽卡右列 3 饮料格 */
    private fun buildRemoteViews(
        context: Context,
        widgetData: SharedPreferences,
    ): RemoteViews {
        val views = RemoteViews(
            context.packageName,
            R.layout.water_llama_widget
        )

        // 目标 + 百分比（Dart 侧算好传入）
        views.setTextViewText(R.id.widget_goal, widgetData.getString(KEY_GOAL_LABEL, "2.5升"))
        views.setTextViewText(R.id.widget_percent, widgetData.getString(KEY_PERCENT, "0%"))

        // 连续徽章（白圆固定，数字居中；可在小组件设置里关闭）
        val streakDays = widgetData.getString(KEY_STREAK, null)?.toIntOrNull() ?: 0
        views.setTextViewText(R.id.widget_streak, "$streakDays")
        views.setViewVisibility(
            R.id.widget_streak_badge,
            if (widgetData.getBoolean(KEY_SHOW_STREAK, true)) View.VISIBLE
            else View.INVISIBLE
        )

        // 主题色背景 + 文字深浅（bg_color == -1 表示默认白底深字）
        val bgColor = widgetData.readIntSafe(KEY_BG_COLOR, -1)
        if (bgColor != -1) {
            views.setInt(R.id.widget_bg_img, "setColorFilter", bgColor)
        }
        val onDark = widgetData.getBoolean(KEY_DARK_TEXT, false)
        val textMain = if (onDark) Color.WHITE else TEXT_DARK
        val textSub = if (onDark) 0xB3FFFFFF.toInt() else TEXT_GRAY
        views.setTextColor(R.id.widget_goal, textMain)
        views.setTextColor(R.id.widget_percent, textSub)

        // 角色插画：Dart 侧按当前点亮/填充状态离屏渲染 16 帧波浪相位 PNG
        // （与 App 内同款 AnimalSilhouette，phase 0..15/16），写入
        // character_frame_0..15 → ViewFlipper 在 launcher 进程内自动轮播，
        // App 退后台/被杀后液体动画仍持续。帧不足 2 张时回退静态单图
        // （character_icon_path 指针 / 旧 character_icon / 默认插画）
        // 注意：RemoteViews 位图总量有 ~15.5MB 系统硬上限
        // （ensureWidgetViewsMemoryLimitLocked，超限直接 IllegalArgumentException
        // 崩掉 App 进程），16 帧原分辨率必超 → 解码统一降采样到单帧 ≤440px
        val frameBmps = (0 until WIDGET_FRAME_COUNT).mapNotNull { i ->
            widgetData.getString(KEY_CHARACTER_FRAME.format(i), null)?.let {
                try {
                    decodeCapped(it, MAX_FRAME_PX)
                } catch (_: Exception) {
                    null
                }
            }
        }
        if (frameBmps.size >= 2) {
            frameBmps.forEachIndexed { idx, bmp ->
                views.setImageViewBitmap(frameId(idx), bmp)
            }
            // 动画层接管；隐藏静态层避免重叠
            views.setViewVisibility(R.id.widget_character, View.INVISIBLE)
            views.setViewVisibility(R.id.widget_character_flipper, View.VISIBLE)
        } else {
            val charPath = widgetData.getString(KEY_CHARACTER_PATH, null)
                ?: widgetData.getString(KEY_CHARACTER, null)
            if (!charPath.isNullOrEmpty()) {
                try {
                    val bmp = decodeCapped(charPath, MAX_FRAME_PX)
                    if (bmp != null) views.setImageViewBitmap(R.id.widget_character, bmp)
                } catch (_: Exception) {
                }
            }
            views.setViewVisibility(R.id.widget_character, View.VISIBLE)
            views.setViewVisibility(R.id.widget_character_flipper, View.INVISIBLE)
        }

        // 饮料格底色（彩色饮料按钮开关；-1 = 默认半透明灰白）。
        // 容量/名称文字颜色固定深/灰，与 App 内预览卡保持一致
        val tileColor = widgetData.readIntSafe(KEY_TILE_COLOR, -1)
        if (tileColor != -1) {
            for (i in 1..3) {
                views.setInt(tileId(i), "setColorFilter", tileColor)
            }
        }

        // 右列饮料格：容量/名称/饮品图标（content:// FileProvider URI）
        for (i in 1..3) {
            val ml = widgetData.getString("drink${i}_ml", null)
            val name = widgetData.getString("drink${i}_name", null)
            val icon = widgetData.getString("drink${i}_icon", null)
            val has = !ml.isNullOrEmpty()
            views.setViewVisibility(mlId(i), if (has) View.VISIBLE else View.INVISIBLE)
            views.setViewVisibility(nameId(i), if (!name.isNullOrEmpty()) View.VISIBLE else View.INVISIBLE)
            views.setViewVisibility(iconId(i), if (!icon.isNullOrEmpty()) View.VISIBLE else View.INVISIBLE)
            if (!name.isNullOrEmpty()) views.setTextViewText(nameId(i), name)
            if (has) views.setTextViewText(mlId(i), ml)
            if (!icon.isNullOrEmpty()) {
                // 自家进程直接解码 PNG → setImageViewBitmap。
                // 不用 setImageViewUri(FileProvider)：launcher 侧加载 content://
                // 会被权限拒绝（SecurityException → 整份 RemoteViews 应用失败）
                try {
                    val bmp = decodeCapped(icon, 220) // 图标显示 ~24dp，220px 绰绰有余
                    if (bmp != null) views.setImageViewBitmap(iconId(i), bmp)
                } catch (_: Exception) {
                }
            }
        }

        // 点击整卡打开应用主界面；点击饮料格发后台广播：插件在 headless
        // Dart 引擎里执行录入回调直接写库并刷新小组件，App UI 不拉起
        // （Dart 侧回调经 HomeWidget.registerInteractivityCallback 注册）
        val launch = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        views.setOnClickPendingIntent(R.id.widget_root, launch)
        for (i in 1..3) {
            views.setOnClickPendingIntent(
                btnId(i),
                HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("waterllama://quick-add?slot=$i")
                )
            )
        }
        return views
    }

    private fun mlId(i: Int) =
        when (i) { 1 -> R.id.widget_d1_ml; 2 -> R.id.widget_d2_ml; else -> R.id.widget_d3_ml }

    private fun nameId(i: Int) =
        when (i) { 1 -> R.id.widget_d1_name; 2 -> R.id.widget_d2_name; else -> R.id.widget_d3_name }

    private fun iconId(i: Int) =
        when (i) { 1 -> R.id.widget_d1_icon; 2 -> R.id.widget_d2_icon; else -> R.id.widget_d3_icon }

    private fun tileId(i: Int) =
        when (i) { 1 -> R.id.widget_d1_tile; 2 -> R.id.widget_d2_tile; else -> R.id.widget_d3_tile }

    private fun frameId(i: Int) = when (i) {
        0 -> R.id.widget_char_f0; 1 -> R.id.widget_char_f1
        2 -> R.id.widget_char_f2; 3 -> R.id.widget_char_f3
        4 -> R.id.widget_char_f4; 5 -> R.id.widget_char_f5
        6 -> R.id.widget_char_f6; 7 -> R.id.widget_char_f7
        8 -> R.id.widget_char_f8; 9 -> R.id.widget_char_f9
        10 -> R.id.widget_char_f10; 11 -> R.id.widget_char_f11
        12 -> R.id.widget_char_f12; 13 -> R.id.widget_char_f13
        14 -> R.id.widget_char_f14; else -> R.id.widget_char_f15
    }

    private fun btnId(i: Int) =
        when (i) { 1 -> R.id.widget_d1_btn; 2 -> R.id.widget_d2_btn; else -> R.id.widget_d3_btn }

    companion object {
        private const val KEY_GOAL_LABEL = "goal_label"
        private const val KEY_PERCENT = "percent"
        private const val KEY_STREAK = "streak_days"
        private const val KEY_BG_COLOR = "bg_color"
        private const val KEY_DARK_TEXT = "dark_text"
        private const val KEY_SHOW_STREAK = "streak_badge"
        private const val KEY_TILE_COLOR = "tile_color"
        private const val KEY_CHARACTER = "character_icon"
        private const val KEY_CHARACTER_PATH = "character_icon_path"

        /** 液体波浪动画帧（character_frame_0..15），ViewFlipper 自动轮播 */
        private const val WIDGET_FRAME_COUNT = 16
        private const val KEY_CHARACTER_FRAME = "character_frame_%d"

        /** 单帧位图边长上限（px）：单套布局 × 16 帧 × 440² × 4B ≈ 12.4MB，
         *  守住 RemoteViews ~15.5MB 位图总内存硬限 */
        private const val MAX_FRAME_PX = 440

        private val TEXT_DARK = Color.parseColor("#1C1C1E")
        private val TEXT_GRAY = Color.parseColor("#9E9EA4")

        /** 静态全量刷新：遍历当前所有小组件实例（供 Dart/原生侧主动触发） */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, WaterLlamaWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            WaterLlamaWidgetProvider()
                .onUpdate(context, manager, ids, HomeWidgetPlugin.getData(context))
        }
    }
}
