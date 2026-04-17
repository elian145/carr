import Flutter
import UIKit
import Firebase
import GoogleMaps

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
    let isPlaceholder = googleMapsApiKey.uppercased().hasPrefix("YOUR_GOOGLE_MAP") || googleMapsApiKey == "YOUR_GOOGLE_MAPS_IOS_KEY"
    NSLog("[Maps] bundleId=%@ keyLen=%d startsWithAIza=%@ placeholder=%@", bundleId, googleMapsApiKey.count, looksLikeApiKey ? "true" : "false", isPlaceholder ? "true" : "false")
    // The SDK can terminate the process if a GMSMapView is created without provideAPIKey being called.
    // Call it unconditionally with a sentinel when missing to keep the app alive and surface a clear
    // "invalid key" signal in logs rather than a hard crash.
    let effectiveKey = googleMapsApiKey.isEmpty ? "MISSING_GOOGLE_MAPS_IOS_KEY" : googleMapsApiKey
    GMSServices.provideAPIKey(effectiveKey)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
