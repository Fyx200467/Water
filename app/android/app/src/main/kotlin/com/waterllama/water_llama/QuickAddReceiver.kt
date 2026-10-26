package com.waterllama.water_llama

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * 小组件饮品格快捷录入 Receiver（vivo OriginOS 兼容·原生快速路径）
 *
 * 真机实测（vivo S15 Pro / OriginOS）：点按饮品格虽会放行拉起进程，但约 5 秒
 * 后即被 cgroup freezer 冻结（/proc/<pid>/cgroup → freezer:/frozen，AMS 层
 * isFrozen 仍为 false）。headless Flutter 引擎冷启动 + Dart 回调链（建容器/
 * 加载设置/写库/重绘）远超该冻结窗口——无论 JobIntentService 还是 goAsync
 * 内联执行，链路都在中途被冻，桌面永不刷新（dumpsys appwidget 的
 * RemoteViews 哈希纹丝不动，点按的水只有打开 App 后才「补现」）。
 *
 * 因此这里完全不碰 Flutter 引擎，纯原生 SharedPreferences 计算 + 直接调
 * provider 重绘，全程毫秒级，冻结来不及介入：
 * 1. 读 `drink{slot}_ml_value`（Dart 同步时写入的槽位容量数值）
 * 2. `widget_today_ml` += ml（`widget_date` 跨天则归零重计）
 * 3. 重算 percent/goal_num/goal_unit（与 Dart 侧 home_widget_sync.dart 同公式）
 * 4. 追加 `native_pending_adds` 队列（"slot:ml:ts:beverageId|..."，App 下次
 *    前台时 drain 成正式录入记录（DrinkEntry 走 DB，统计/回看完全一致）
 * 5. 局部更新小组件（只推数据不重排版面，见 updateDataOnly 注释）
 *
 * 并发保护：广播可在任意时刻重入（连点、跟 Dart 同步交错），
 * 读-改-写偏好必须串行，否则丢队列条目 / 总量被后写覆盖。
 */
class QuickAddReceiver : BroadcastReceiver() {

  companion object {
    private const val TAG = "QuickAddReceiver"
    private const val KEY_TODAY_ML = "widget_today_ml"
    private const val KEY_GOAL_ML = "goal_ml"
    private const val KEY_DATE = "widget_date"
    private const val KEY_PENDING = "native_pending_adds"
    private const val KEY_STREAK = "streak_days"
    private const val KEY_STREAK_ANCHOR = "streak_anchor"

    /** 读改写串行锁（进程内即可：写入方只有本 Receiver） */
    private val WRITE_LOCK = Any()
  }

  override fun onReceive(context: Context, intent: Intent) {
    val data = intent.data?.toString() ?: ""
    if (!data.startsWith("waterllama://quick-add")) {
      // 非快捷录入意图：交回插件原 Receiver 处理（兜底，理论上不会到这里）
      es.antonborri.home_widget.HomeWidgetBackgroundReceiver().onReceive(context, intent)
      return
    }
    // 触觉反馈：主线程立即震，不等后台线程（点按手感）
    vibrate(context)
    // 提示音：设置页「小部件声音」开关同步在 widget_sounds 键上
    playSoundIfEnabled(context)
    // goAsync + 工作线程：onUpdate 里 BitmapFactory 解码帧/图标非瞬时，
    // 不能占主线程；finish() 收尾释放广播派发窗口
    val pending = goAsync()
    val appContext = context.applicationContext
    Thread {
      try {
        handleQuickAdd(appContext, data)
      } catch (e: Exception) {
        Log.e(TAG, "快捷录入失败", e)
      } finally {
        pending.finish()
      }
    }.start()
  }

  private fun handleQuickAdd(context: Context, data: String) = synchronized(WRITE_LOCK) {
    val slot = Uri.parse(data).getQueryParameter("slot")?.toIntOrNull() ?: return
    if (slot !in 1..3) return
    val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)
    // 双保险闸门（方案 B）：未完成初始化引导拒绝录入（Dart 侧方案 A
    // 已把录入数值清 0，此处防历史残留/闸门漏网）。小组件未初始化时
    // 只展示不可录入
    if (!prefs.getBoolean("profile_initialized", false)) return
    // 槽位容量数值（home_widget_sync.dart 每次同步写入；未配置则不录入）
    val ml = (prefs.all["drink${slot}_ml_value"] as? Number)?.toInt() ?: 0
    if (ml <= 0) return
    // 水合折算量：与 App 内 sumEffective 口径一致。负数合法（红酒等
    // 脱水类饮品折算后为负，点了要「倒扣」水量），仅 -1 = 未折算哨兵
    // （Dart 侧 effectiveMl 为 null 时写入）→ 回退按原容量累加；
    // 0 合法（无水合贡献的饮品）。正式记录队列仍存原容量，App drain
    // 后走 DrinkEntry.create 折算管线，两端一致
    val rawEff = (prefs.all["drink${slot}_eff_ml_value"] as? Number)?.toInt()
    val addMl = if (rawEff != null && rawEff != -1) rawEff else ml

    // 跨天判定走「逻辑日」：分界是用户设置的一天重置时刻（如 03:00），
    // 不是午夜。原生读不到 App 设置，故 Dart 同步时下发 reset_hour/
    // reset_minute，此处按同一口径折算今天的逻辑日 key
    val resetMinutes =
        ((prefs.all["reset_hour"] as? Number)?.toInt() ?: 0) * 60 +
            ((prefs.all["reset_minute"] as? Number)?.toInt() ?: 0)
    val now = Calendar.getInstance()
    val logical = Calendar.getInstance().apply {
      timeInMillis = now.timeInMillis
      if (now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE) < resetMinutes) {
        add(Calendar.DAY_OF_MONTH, -1)
      }
    }
    val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val today = fmt.format(logical.time)
    val yesterday = fmt.format(Calendar.getInstance().apply {
      timeInMillis = logical.timeInMillis
      add(Calendar.DAY_OF_MONTH, -1)
    }.time)

    val savedDate = prefs.getString(KEY_DATE, null)
    val todayMl = if (savedDate == today) {
      (prefs.all[KEY_TODAY_ML] as? Number)?.toInt() ?: 0
    } else 0

    val newTotal = todayMl + addMl
    val goal = (prefs.all[KEY_GOAL_ML] as? Number)?.toInt() ?: 0

    // 与 Dart 侧同公式：percent = (today*100/goal).round()，封顶 100
    // （App 显示层同样封顶，否则超目标后桌面显示 114% 之类）
    val percent =
        if (goal > 0) Math.round(newTotal * 100.0 / goal).toInt().coerceIn(0, 100) else 0

    // 追加待入库队列，App 前台 drain 成正式记录（携带点按时间戳与
    // 点按当时的饮品 id：用户之后在设置页换了饮品格也不会入错饮品）
    val beverageId = prefs.getString("drink${slot}_id", null) ?: ""
    val item = "$slot:$ml:${System.currentTimeMillis()}:$beverageId"
    val oldQueue = prefs.getString(KEY_PENDING, null)
    val newQueue = if (oldQueue.isNullOrEmpty()) item else "$oldQueue|$item"

    val editor = prefs.edit()
        .putString(KEY_DATE, today)
        .putInt(KEY_TODAY_ML, newTotal)
        .putString(KEY_PENDING, newQueue)
        .putString("goal_num", volumeNumber(newTotal))
        .putString("goal_unit", volumeUnit(newTotal))
        .putBoolean("streak_done", goal > 0 && newTotal >= goal)
        .putString("percent", "$percent%")

    // 液体填充等级帧：Dart 侧预渲 0..100% 每 10% 一档 × 16 波浪相位
    // （character_level_N_P）。按新百分比就近取档，16 相位 1:1 写入全部
    // 动画帧槽位 → ViewFlipper 以原生同款 100ms/帧 轮播，动画流畅不中断、
    // 液面即时到新档位；下次 Dart 同步重渲当前填充态动画自动恢复
    val level =
        (Math.round(percent / 10.0).toInt() * 10).coerceIn(0, 100)
    val phases =
        (0..15).map { prefs.getString("character_level_${level}_$it", null) }
    if (phases.all { it != null }) {
      for (i in 0..15) editor.putString("character_frame_$i", phases[i])
      editor.remove("character_icon")
    } else {
      // 档位帧未就绪（首次同步尚未渲完）→ 回退旧单帧静态液面
      val single = prefs.getString("character_level_$level", null)
      if (single != null) {
        editor.putString("character_icon", single)
        for (i in 0..15) editor.remove("character_frame_$i")
      }
    }

    // 天数徽章：本次是「今天第一笔录入」时连续天数 +1。对齐 Dart
    // checkinDaysProvider 语义：今天有任何条目 → 连续链纳入今天，
    // 否则从昨天起数。
    // 断签判定：streak_anchor = 连续链已计入的最后一个逻辑日（Dart 同步
    // 下发）。anchor 是昨天 → +1；anchor 是今天 → 已计入不再加；其余
    // （隔了多天没喝 / 首次使用）→ 重置为 1。此前无 anchor 时一律 +1，
    // 隔天没喝水也会「续签」，与 App 内数字打架
    if (todayMl <= 0) {
      val raw = prefs.all[KEY_STREAK]
      val oldStreak = when (raw) {
        is Number -> raw.toInt()
        is String -> raw.toIntOrNull() ?: 0
        else -> 0
      }
      val anchor = prefs.getString(KEY_STREAK_ANCHOR, null) ?: ""
      val next = when (anchor) {
        today -> oldStreak
        yesterday -> oldStreak + 1
        else -> 1
      }
      editor.putString(KEY_STREAK, "$next")
      editor.putString(KEY_STREAK_ANCHOR, today)
    }
    editor.commit()

    // 局部更新重绘：只换文案/位图/颜色，不动布局尺寸（全量 updateAppWidget
    // 会让 launcher 重新测量整套视图，观感是「点一下整个小组件抖一下」）
    val manager = AppWidgetManager.getInstance(context)
    val ids =
        manager.getAppWidgetIds(ComponentName(context, WaterLlamaWidgetProvider::class.java))
    if (ids != null && ids.isNotEmpty()) {
      WaterLlamaWidgetProvider.updateDataOnly(context, manager, ids)
    }
  }

  /** 点按饮品格触觉反馈（短促 tick；设备无马达/被系统关掉时静默） */
  private fun vibrate(context: Context) {
    try {
      val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
            ?.defaultVibrator
      } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
      }
      if (vibrator == null || !vibrator.hasVibrator()) return
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        vibrator.vibrate(VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE))
      } else {
        @Suppress("DEPRECATION")
        vibrator.vibrate(20)
      }
    } catch (_: Exception) {
      // 触觉反馈失败不影响录入
    }
  }

  /** 小组件点按「加水成功」音效（res/raw/water_add.m4a）
   *  开关由 App 设置页「小部件声音」同步到 widget_sounds 键 */
  private fun playSoundIfEnabled(context: Context) {
    try {
      val prefs = HomeWidgetPlugin.getData(context)
      if (!prefs.getBoolean("widget_sounds", true)) return
      val mp = MediaPlayer.create(context, R.raw.water_add) ?: return
      mp.setOnCompletionListener {
        try {
          it.release()
        } catch (_: Exception) {
        }
      }
      mp.start()
    } catch (_: Exception) {
      // 音频设备不可用时静默，不影响录入
    }
  }

  /** 与 home_widget_sync.dart 同格式：≥1L 数字固定一位小数 + 单位「升」，
   *  不足 1L 数字为整数 + 单位「ml」（与 App 预览卡一致） */
  private fun volumeNumber(ml: Int): String =
      if (ml >= 1000) String.format(Locale.US, "%.1f", ml / 1000.0) else "$ml"

  private fun volumeUnit(ml: Int): String = if (ml >= 1000) "升" else "ml"
}
