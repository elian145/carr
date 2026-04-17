import Flutter
import UIKit
import Firebase
import GoogleMaps

/// Walks navigation/tab/presented controllers to find the engine host.
private func maps_findFlutterViewController(from root: UIViewController?) -> FlutterViewController? {
  guard let root = root else { return nil }
  if let f = root as? FlutterViewController { return f }
  if let nav = root as? UINavigationController {
    return maps_findFlutterViewController(from: nav.visibleViewController)
  }
  if let tab = root as? UITabBarController {
    return maps_findFlutterViewController(from: tab.selectedViewController)
  }
  if let presented = root.presentedViewController {
    return maps_findFlutterViewController(from: presented)
  }
  return nil
}

/// `window` is not always set on `FlutterAppDelegate` during `didFinishLaunching`; also check active scenes.
private func maps_hostFlutterViewController(_ delegate: FlutterAppDelegate) -> FlutterViewController? {
  if let f = maps_findFlutterViewController(from: delegate.window?.rootViewController) {
    return f
  }
  for scene in UIApplication.shared.connectedScenes {
    guard let windowScene = scene as? UIWindowScene else { continue }
    for window in windowScene.windows where window.isKeyWindow || window.windowScene != nil {
      if let f = maps_findFlutterViewController(from: window.rootViewController) {
        return f
      }
    }
  }
  return nil
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Mirrors native `GMSServices.provideAPIKey` decision for the Dart MethodChannel.
  private var mapsSdkConfiguredForChannel = false

  private func registerMapsConfigChannelIfPossible() {
    guard let controller = maps_hostFlutterViewController(self) else { return }
    let channel = FlutterMethodChannel(
      name: "com.example.car_listing_app/google_maps_config",
      binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: nil, details: nil))
        return
      }
      if call.method == "isIosGoogleMapsSdkConfigured" {
        result(NSNumber(value: self.mapsSdkConfiguredForChannel))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let filePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
       let options = FirebaseOptions(contentsOfFile: filePath) {
      FirebaseApp.configure(options: options)
    }

    let googleMapsApiKeyRaw = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    let googleMapsApiKey = googleMapsApiKeyRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    mapsSdkConfiguredForChannel =
      googleMapsApiKey.count >= 30 &&
      !googleMapsApiKey.uppercased().hasPrefix("YOUR_GOOGLE_MAP")

    if mapsSdkConfiguredForChannel {
      GMSServices.provideAPIKey(googleMapsApiKey)
    }

    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    registerMapsConfigChannelIfPossible()
    DispatchQueue.main.async { [weak self] in
      self?.registerMapsConfigChannelIfPossible()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.registerMapsConfigChannelIfPossible()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.registerMapsConfigChannelIfPossible()
    }

    return launched
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    registerMapsConfigChannelIfPossible()
  }
}
