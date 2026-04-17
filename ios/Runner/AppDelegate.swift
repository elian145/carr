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
    // Configure Firebase only if a valid GoogleService-Info.plist is bundled.
    // This avoids crash-on-launch for sideloaded builds without Firebase config.
    if let filePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
       let options = FirebaseOptions(contentsOfFile: filePath) {
      FirebaseApp.configure(options: options)
    }
    // Google Maps SDK (same API key project as Android is fine; iOS key restrictions differ).
    if let raw = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String {
      let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if !key.isEmpty && !key.hasPrefix("YOUR_GOOGLE_MAPS") {
        GMSServices.provideAPIKey(key)
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
