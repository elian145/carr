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

    // Google Maps iOS SDK: must call provideAPIKey before any GMSMapView is created.
    // If the key is missing or still a placeholder, skip initialization — Flutter will
    // avoid embedding GoogleMap (otherwise the process is killed).
    let googleMapsApiKeyRaw = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    let googleMapsApiKey = googleMapsApiKeyRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    let iosMapsSdkConfigured =
      googleMapsApiKey.count >= 30 &&
      !googleMapsApiKey.uppercased().hasPrefix("YOUR_GOOGLE_MAP")

    if iosMapsSdkConfigured {
      GMSServices.provideAPIKey(googleMapsApiKey)
    }

    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    func registerMapsConfigChannel(on controller: FlutterViewController) {
      let channel = FlutterMethodChannel(
        name: "com.example.car_listing_app/google_maps_config",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        if call.method == "isIosGoogleMapsSdkConfigured" {
          // Use NSNumber so the Flutter standard codec always yields a bool on the Dart side.
          result(NSNumber(value: iosMapsSdkConfigured))
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      registerMapsConfigChannel(on: controller)
    } else {
      DispatchQueue.main.async { [weak self] in
        guard let self = self,
              let controller = self.window?.rootViewController as? FlutterViewController else {
          return
        }
        registerMapsConfigChannel(on: controller)
      }
    }
    // Window can attach slightly after super.application; register again so Dart never misses the channel.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self = self,
            let controller = self.window?.rootViewController as? FlutterViewController else {
        return
      }
      registerMapsConfigChannel(on: controller)
    }

    return launched
  }
}
