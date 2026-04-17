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
    let looksValid =
      googleMapsApiKey.count >= 30 &&
      !googleMapsApiKey.uppercased().hasPrefix("YOUR_GOOGLE_MAP")

    if looksValid {
      GMSServices.provideAPIKey(googleMapsApiKey)
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
