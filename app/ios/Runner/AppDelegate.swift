import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // FlutterAppDelegate 已遵循 UNUserNotificationCenterDelegate，
    // 这里只需把通知中心回调指向它，flutter_local_notifications 才能在前台展示提醒
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 本工程走 UIScene 生命周期：此时 window / FlutterViewController 尚未就绪，
    // 通道必须用 applicationRegistrar 的 messenger 创建（官方迁移指引）
    let messenger = engineBridge.applicationRegistrar.messenger()

    // 音效通道：与 Android MainActivity 的 waterllama/sound 同名同参数
    FlutterMethodChannel(name: "waterllama/sound", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "play" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.waterPlayer.play()
        result(true)
      }

    // 通知设置通道：跳本应用的系统设置页（通知权限被永久拒绝时使用）
    FlutterMethodChannel(name: "app.notification.settings", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "open" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          result(opened)
        }
      }

    // 图标切换通道：与 Android MainActivity 的 app.icon.switcher 同名同参数
    FlutterMethodChannel(name: "app.icon.switcher", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "setIcon" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let args = call.arguments as? [String: Any]
        let alias = (args?["alias"] as? String) ?? ""
        // Android 传的是 activity-alias 全名（包名.AppIcon_<id>），
        // iOS 取 "<id>" 映射到 Assets.xcassets 里的 Icon_<id> 图标集
        let iconId = alias.components(separatedBy: "AppIcon_").last ?? alias
        // 默认图标（glyph2_drop0 就是主图标，不单独做备用图标集）
        let alternate: String? =
          (iconId.isEmpty || iconId == "default" || iconId == "glyph2_drop0")
          ? nil : "Icon_\(iconId)"
        DispatchQueue.main.async {
          guard UIApplication.shared.supportsAlternateIcons else {
            result(false)
            return
          }
          if UIApplication.shared.alternateIconName == alternate {
            result(true)
            return
          }
          UIApplication.shared.setAlternateIconName(alternate) { error in
            if let error = error {
              NSLog("[icon] setAlternateIconName failed: \(error)")
              result(false)
            } else {
              result(true)
            }
          }
        }
      }
  }

  /// 加水音效播放器（懒加载，复用同一份素材）
  private let waterPlayer = WaterSoundPlayer()
}

/// 播放「加水成功」音效：assets/audio/water_add.m4a
///
/// 音频放在 Flutter asset 里（与 Android res/raw 同一份素材），
/// 通过 FlutterDartProject 的 asset key 在 main bundle 里定位，
/// 避免往 Xcode 工程 Resources 里额外添加文件。
final class WaterSoundPlayer {
  private var player: AVAudioPlayer?
  private var loadFailed = false

  func play() {
    guard let player = ensurePlayer() else { return }
    do {
      // ambient + mixWithOthers：跟随静音键，且不打断用户正在播放的音乐
      try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // 音频会话被占用时仍尝试播放
    }
    if player.isPlaying {
      player.stop()
    }
    player.currentTime = 0
    player.play()
  }

  private func ensurePlayer() -> AVAudioPlayer? {
    if let player = player {
      return player
    }
    if loadFailed {
      return nil
    }
    let key = FlutterDartProject.lookupKey(forAsset: "assets/audio/water_add.m4a")
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      loadFailed = true
      return nil
    }
    do {
      let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      p.volume = 0.9
      p.prepareToPlay()
      player = p
      return p
    } catch {
      loadFailed = true
      return nil
    }
  }
}
