package com.waterllama.water_llama

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
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
            renderAndPush(context, widgetData, appWidgetManager, appWidgetId)
        }
    }

    /** 网格密度变化/调整大小时回调：按新分配尺寸重建（5x9 等高密度
     *  网格下 2 行高度 ~150dp，标准内容竖向溢出会挤压变形） */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        renderAndPush(context, HomeWidgetPlugin.getData(context), appWidgetManager, appWidgetId)
    }

    /** 响应式尺寸档位：按实例分配的**高度**切标准/紧凑档。
     *  宽度判据在 vivo 上 4x6 与 5x9 区间重叠（实测 4x6 也会报 <300dp）
     *  曾致误判；高度才是两种网格的区分信号（4x6 两行 ~180dp，
     *  5x9 两行 ~150dp）。RemoteViews 动作跨次残留，两档都显式全量
     *  设置。相关 API 均为 API 31+（vivo S15 Pro = Android 12+） */
    private fun applySizeProfile(
        context: Context,
        views: RemoteViews,
        manager: AppWidgetManager,
        appWidgetId: Int
    ) {
        if (Build.VERSION.SDK_INT < 31) return
        val opts = manager.getAppWidgetOptions(appWidgetId)
        val maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        val compact = maxH in 1..164

        // 占格固定 4x2（widget_info targetCellWidth=4；minWidth 120dp
        // 在窄格网格 ceil 不会超过 4，minHeight 100dp 不会超过 2 行，
        // 无 resizeMode → 不可拉伸）。紧凑档（5x9 等高密度网格：4 列
        // 卡面 ~240dp × ~130-150dp 高）中等尺寸；标准档（4x6：4 列
        // ~296dp × ~180dp 高）尽量填满
        // 羊驼尺寸：按实测分配高度自适应（maxH − 上下 padding 24dp −
        // 边距 8dp）：4×6 两行 maxH≈157dp → 125dp，5×9 两行 ≈150dp →
        // 118dp。窄卡（3 列）饮品格占右侧大半，加宽度上限 = 卡宽 42%
        // 取小，避免右缘贴到饮品文字；clamp 下限 88 防极端小格、上限
        // 140 防溢出
        val maxW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val wCap = if (maxW > 0) maxW * 0.42f else Float.MAX_VALUE
        val charDp = minOf(maxH - 32f, wCap).coerceIn(88f, 140f)
        for (vid in intArrayOf(R.id.widget_character, R.id.widget_character_flipper)) {
            views.setViewLayoutWidth(vid, charDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(vid, charDp, TypedValue.COMPLEX_UNIT_DIP)
        }
        // 角色水平位置：布局层 overlay 锚定，羊驼居中于第一格（占卡宽
        // 68%）→ 中心落在卡宽 34% 处，窄卡上远离饮品列，与列内容宽度
        // 无关，provider 不再干预
        // 左上数字位图框（固定 dp，防 launcher 量测缺陷）：窄卡同步收
        views.setViewLayoutWidth(R.id.widget_goal_img,
            if (compact) 48f else 56f, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutHeight(R.id.widget_goal_img,
            if (compact) 20f else 24f, TypedValue.COMPLEX_UNIT_DIP)
        // 天数徽章
        views.setViewLayoutWidth(R.id.widget_streak_badge,
            if (compact) 30f else 34f, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutHeight(R.id.widget_streak_badge,
            if (compact) 30f else 34f, TypedValue.COMPLEX_UNIT_DIP)
        // 右列三行各占列高 1/3（XML weight=1），行高按实测分配高度推算
        // （maxH − 上下 padding 24dp），按钮/图标/字号随行高连续缩放，
        // 替代原固定两档——5×9 等高密度网格高度介于两档之间时不再被
        // 挤压变形。+ 号字号与 ml 数字同步
        val rowH = (maxH - 24f) / 3f
        val tileH = (rowH - 8f).coerceIn(30f, 44f)
        val tileW = (tileH * 1.41f).coerceIn(42f, 62f)
        val iconDp = (tileH * 0.77f).coerceIn(22f, 34f)
        val textSp = (tileH * 0.34f).coerceIn(11f, 15f)
        for (i in 1..3) {
            views.setViewLayoutWidth(btnId(i), tileW, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(btnId(i), tileH, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutWidth(iconId(i), iconDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(iconId(i), iconDp, TypedValue.COMPLEX_UNIT_DIP)
            // + 号定位：固定宽盒（按钮宽 48%）内居中 → 中心恒在按钮宽
            // 24% 处，随按钮等比内缩（XML 无 margin，窄按钮不挤图标）
            views.setViewLayoutWidth(plusId(i), tileW * 0.48f, TypedValue.COMPLEX_UNIT_DIP)
            views.setTextViewTextSize(mlId(i), TypedValue.COMPLEX_UNIT_SP, textSp)
            views.setTextViewTextSize(plusId(i), TypedValue.COMPLEX_UNIT_SP, textSp)
        }
        // 极限矮档（maxH ≤ 134）：行内竖向放不下「ml 数字 + 饮品名」两层，
        // 隐藏饮品名只留数字。两态显式设置，防 RemoteViews 动作跨次残留
        val extreme = maxH in 1..134
        for (i in 1..3) {
            views.setViewVisibility(
                nameId(i), if (extreme) View.INVISIBLE else View.VISIBLE)
        }
        views.setTextViewTextSize(
            R.id.widget_percent, TypedValue.COMPLEX_UNIT_SP, if (compact) 11f else 12f)
    }

    /** 目标数字+单位绘成位图（18sp 粗体数字 + 12sp 粗体单位基线对齐）。
     *  vivo launcher 对 RemoteViews TextView 的文本量测有缓存缺陷，
     *  位图 + 固定 dp ImageView 完全脱离量测路径，不可能再被裁 */
    private fun goalBitmap(
        context: Context,
        num: String,
        unit: String,
        onDark: Boolean
    ): Bitmap? {
      return try {
        val d = context.resources.displayMetrics.density
        val numPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
          color = if (onDark) Color.WHITE else TEXT_DARK
          textSize = 18f * d
          typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val unitPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
          color = if (onDark) Color.WHITE else TEXT_DARK
          textSize = 12f * d
          typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val numW = numPaint.measureText(num)
        val unitW = unitPaint.measureText(unit)
        val h = (26f * d).toInt()
        val w = (numW + unitW + 2f * d).toInt().coerceAtMost((96f * d).toInt())
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawText(num, 0f, h - 5f * d, numPaint)
        c.drawText(unit, numW + 1f * d, h - 3f * d, unitPaint)
        bmp
      } catch (_: Exception) {
        null
      }
    }

    /** 按上限降采样解码 PNG（inSampleSize 2 的幂）：帧位图总量受
     *  RemoteViews 位图内存硬限，原分辨率解码 16 帧必崩。
     *  downshift：在常规采样之上再整体右移 n 档（帧尺寸减半^n），
     *  供超限降级重试使用 */
    private fun decodeCapped(path: String, maxPx: Int, downshift: Int = 0): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > maxPx) {
            sample *= 2
        }
        sample = (sample shl downshift).coerceAtLeast(1)
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeFile(path, opts)
    }

    /** 渲染并推送一次小组件更新。帧位图总量受系统硬限且各厂商差异极
     *  大（vivo ~15.5MB，ColorOS 仅 ~6.9MB，实测 16 帧全画质 9.6MB 在
     *  OPPO 上 IllegalArgumentException 崩进程 + 组件永不渲染），先按
     *  全画质推送，被拒则帧尺寸逐档减半重试：vivo 恒走首档画质无损，
     *  OPPO 收敛到 1/2 档（~2.4MB），最低档仍被拒则保持旧渲染不崩 */
    private fun renderAndPush(
        context: Context,
        widgetData: SharedPreferences,
        manager: AppWidgetManager,
        appWidgetId: Int
    ) {
        for (downshift in 0..2) {
            val views = buildRemoteViews(context, widgetData, frameDownshift = downshift)
            applySizeProfile(context, views, manager, appWidgetId)
            try {
                manager.updateAppWidget(appWidgetId, views)
                return
            } catch (_: IllegalArgumentException) {
                if (downshift == 2) return
            }
        }
    }

    /** 组装小组件视图：读取 Dart 侧写入的共享数据 → 填充文案/颜色/饮品图标。
     *  唯一固定样式（对标竞品「柠檬喝水」：所有设备/所有厂商只此一种，
     *  不可更改）= 全宽卡右列 3 饮料格 */
    private fun buildRemoteViews(
        context: Context,
        widgetData: SharedPreferences,
        frameDownshift: Int = 0,
    ): RemoteViews {
        val views = RemoteViews(
            context.packageName,
            R.layout.water_llama_widget
        )

        // 目标数字+单位：Canvas 绘成位图（规避 vivo 文本量测缺陷），
        // 白圆/深浅色在位图内直接体现；百分比仍为 TextView（短文案无碍）
        val onDark = widgetData.getBoolean(KEY_DARK_TEXT, false)
        goalBitmap(context,
            widgetData.getString(KEY_GOAL_NUM, "2.5") ?: "2.5",
            widgetData.getString(KEY_GOAL_UNIT, "升") ?: "升", onDark)?.let {
            views.setImageViewBitmap(R.id.widget_goal_img, it)
        }
        views.setTextViewText(R.id.widget_percent, widgetData.getString(KEY_PERCENT, "0%"))

        // 连续徽章（白圆固定，数字居中；可在小组件设置里关闭）。
        // 当日达标（streak_done）时切换到 flipper：✓ 与天数每 2s 轮播
        val streakDays = widgetData.getString(KEY_STREAK, null)?.toIntOrNull() ?: 0
        views.setTextViewText(R.id.widget_streak, "$streakDays")
        views.setTextViewText(R.id.widget_streak_num, "$streakDays")
        val goalDone = widgetData.getBoolean(KEY_STREAK_DONE, false)
        // GONE = 完全移出布局（flipper 必须 VISIBLE 装载才会在 vivo 上轮播，
        // 未达标时的隐藏只能由这里每次重绘显式接管）。达标时静态数字也要
        // 藏起来——flipper 在其上层轮播，静态层不藏会和 ✓ 叠影
        views.setViewVisibility(
            R.id.widget_badge_flipper,
            if (goalDone) View.VISIBLE else View.GONE
        )
        views.setViewVisibility(
            R.id.widget_streak,
            if (goalDone) View.INVISIBLE else View.VISIBLE
        )
        views.setViewVisibility(
            R.id.widget_streak_badge,
            if (widgetData.getBoolean(KEY_SHOW_STREAK, true)) View.VISIBLE
            else View.INVISIBLE
        )

        // 主题色背景 + 文字深浅。注意 RemoteViews 是在既有视图上叠加动作，
        // setColorFilter 无法"清除"——切回白/默认底时必须显式设置对应滤镜，
        // 否则会残留上一次的主题色（用户反馈：选白色不生效）
        val bgColor = widgetData.readIntSafe(KEY_BG_COLOR, -1)
        views.setInt(
            R.id.widget_bg_img, "setColorFilter",
            if (bgColor != -1) bgColor else 0xFFFFFFFF.toInt()
        )
        val textMain = if (onDark) Color.WHITE else TEXT_DARK
        val textSub = if (onDark) 0xB3FFFFFF.toInt() else TEXT_GRAY
        views.setTextColor(R.id.widget_percent, textSub)
        // 徽章数字/✓ 落在固定白色圆底上（圆底不随主题染色）→ 始终深色：
        // 深色背景下若跟随 textMain 会变成白圆上的白字不可读
        views.setTextColor(R.id.widget_streak, TEXT_DARK)
        views.setTextColor(R.id.widget_streak_num, TEXT_DARK)
        views.setTextColor(R.id.widget_streak_check, TEXT_DARK)

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
                    decodeCapped(it, MAX_FRAME_PX, frameDownshift)
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
                    val bmp = decodeCapped(charPath, MAX_FRAME_PX, frameDownshift)
                    if (bmp != null) views.setImageViewBitmap(R.id.widget_character, bmp)
                } catch (_: Exception) {
                }
            }
            views.setViewVisibility(R.id.widget_character, View.VISIBLE)
            views.setViewVisibility(R.id.widget_character_flipper, View.INVISIBLE)
        }

        // 饮料格底色（彩色饮料按钮开关；-1 = 默认灰底 #F1F1F4，同样要
        // 显式覆盖滤镜防止残留上次的颜色）
        val tileColor = widgetData.readIntSafe(KEY_TILE_COLOR, -1)
        val tileFilter =
            if (tileColor != -1) tileColor else 0xFFF1F1F4.toInt()
        for (i in 1..3) {
            views.setInt(tileId(i), "setColorFilter", tileFilter)
        }

        // 右列文字颜色自适应（所有数字/文字跟随所在底色切换深浅，用户
        // 要求）：ml/饮品名在卡面背景上 → 随 dark_text（textMain/textSub
        // 已按背景亮度切好）；+ 号与左侧 ml 文字同色同步变化（用户指定）。
        // 两态显式设置，防 RemoteViews 动作残留
        for (i in 1..3) {
            views.setTextColor(mlId(i), textMain)
            views.setTextColor(nameId(i), textSub)
            views.setTextColor(plusId(i), textMain)
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

        // 点击整卡打开应用主界面；点击饮料格发后台广播：QuickAddReceiver 用
        // goAsync 内联跑 headless Dart 引擎完成录入并刷新小组件，App UI 不拉起
        // （不走插件的 JobIntentService：vivo 会在 Job 执行中冻结进程导致桌面不刷新）
        val launch = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        views.setOnClickPendingIntent(R.id.widget_root, launch)
        for (i in 1..3) {
            val tapIntent =
                Intent(context, QuickAddReceiver::class.java)
                    .setData(Uri.parse("waterllama://quick-add?slot=$i"))
            views.setOnClickPendingIntent(
                btnId(i),
                PendingIntent.getBroadcast(
                    context,
                    i, // 请求码按格区分，避免三个 PendingIntent 相互覆盖
                    tapIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        }
        return views
    }

    private fun mlId(i: Int) =
        when (i) { 1 -> R.id.widget_d1_ml; 2 -> R.id.widget_d2_ml; else -> R.id.widget_d3_ml }

    private fun nameId(i: Int) =
        when (i) { 1 -> R.id.widget_d1_name; 2 -> R.id.widget_d2_name; else -> R.id.widget_d3_name }

    private fun plusId(i: Int) =
        when (i) { 1 -> R.id.widget_d1_plus; 2 -> R.id.widget_d2_plus; else -> R.id.widget_d3_plus }

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
        private const val KEY_GOAL_NUM = "goal_num"
        private const val KEY_GOAL_UNIT = "goal_unit"
        private const val KEY_STREAK_DONE = "streak_done"
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
