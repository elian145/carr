import Flutter
import UIKit
import Firebase
import GoogleMaps
import airbridge_flutter_sdk

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let filePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
       let options = FirebaseOptions(contentsOfFile: filePath) {
      FirebaseApp.configure(options: options)
    }

    // Google Maps iOS SDK — call before any map view is created (Debug uses Info-Debug.plist).
    let googleMapsApiKeyRaw = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    let googleMapsApiKey = googleMapsApiKeyRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    let bundleId = Bundle.main.bundleIdentifier ?? "(unknown)"
    let looksLikeApiKey = googleMapsApiKey.hasPrefix("AIza") && googleMapsApiKey.count >= 30
    let hasUnresolvedBuildVar = googleMapsApiKey.contains("$(IOS_GOOGLE_MAPS_API_KEY)")
    let isMissingOrPlaceholder = googleMapsApiKey.isEmpty || hasUnresolvedBuildVar
    NSLog("[Maps] bundleId=%@ keyLen=%d startsWithAIza=%@ unresolvedOrMissing=%@", bundleId, googleMapsApiKey.count, looksLikeApiKey ? "true" : "false", isMissingOrPlaceholder ? "true" : "false")
    let effectiveKey = googleMapsApiKey.isEmpty ? "MISSING_GOOGLE_MAPS_IOS_KEY" : googleMapsApiKey
    GMSServices.provideAPIKey(effectiveKey)

    let abName = (Bundle.main.object(forInfoDictionaryKey: "AirbridgeAppName") as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let abTok = (Bundle.main.object(forInfoDictionaryKey: "AirbridgeAppToken") as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !abName.isEmpty && !abTok.isEmpty {
      AirbridgeFlutter.initializeSDK(name: abName, token: abTok)
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let abName = (Bundle.main.object(forInfoDictionaryKey: "AirbridgeAppName") as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !abName.isEmpty {
      AirbridgeFlutter.trackDeeplink(url: url)
    }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    let abName = (Bundle.main.object(forInfoDictionaryKey: "AirbridgeAppName") as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !abName.isEmpty {
      AirbridgeFlutter.trackDeeplink(userActivity: userActivity)
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }
}
