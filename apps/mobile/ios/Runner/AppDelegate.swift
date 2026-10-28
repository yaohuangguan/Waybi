import Flutter
import AVFAudio
import CoreLocation
import GoogleMaps
import GoogleNavigation
import UIKit
import UserNotifications
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var systemNavigation: AnyObject?
  private let headingHandler = DeviceHeadingStreamHandler()
  private var googlePicker: WaybiGooglePlacePicker?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    stageFriendsRecovery()
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    if let url = launchOptions?[.url] as? URL {
      ExternalNavigationBridge.shared.receive(url)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// An optional archive copied by device tooling during a bundle-ID migration.
  /// Only Friends data enters preferences; account and other settings stay intact.
  private func stageFriendsRecovery() {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let file = documents.appendingPathComponent("waybi-friends-recovery-v1.json")
    guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          size <= 2_000_000,
          let data = try? Data(contentsOf: file),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          json["memories"] is [[String: Any]],
          let raw = String(data: data, encoding: .utf8) else { return }
    let prefs = UserDefaults.standard
    let pendingKey = "flutter.waybi_friends_v1.pending_restore"
    guard prefs.string(forKey: pendingKey) == nil else { return }
    prefs.set(raw, forKey: pendingKey)
    // Keep the file if preferences cannot be flushed. Dart validates and merges
    // the archive, then clears the staged value only after a successful save.
    if prefs.synchronize() { try? FileManager.default.removeItem(at: file) }
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if ExternalNavigationBridge.shared.receive(url) { return true }
    return super.application(application, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(name: "waybi/google_place_picker", binaryMessenger: engineBridge.applicationRegistrar.messenger())
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "open", let args = call.arguments as? [String: Any],
              let raw = args["url"] as? String, let url = URL(string: raw),
              url.scheme == "https", url.host == "waybi.co", url.path == "/api/search/google",
              url.user == nil, url.password == nil, url.port == nil else {
          result(FlutterError(code: "invalid_picker", message: "Invalid search page", details: nil)); return
        }
        DispatchQueue.main.async {
          guard let self, self.googlePicker == nil, let root = self.window?.rootViewController else {
            result(nil); return
          }
          let picker = WaybiGooglePlacePicker(url: url) { [weak self] value in
            self?.googlePicker = nil
            result(value)
          }
          self.googlePicker = picker
          let navigation = UINavigationController(rootViewController: picker)
          navigation.modalPresentationStyle = .fullScreen
          var presenter = root
          while let presented = presenter.presentedViewController { presenter = presented }
          presenter.present(navigation, animated: true)
        }
      }
    ExternalNavigationBridge.shared.attach(to: engineBridge.applicationRegistrar.messenger())
    FlutterMethodChannel(
      name: "waybi/system_navigation",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        guard #available(iOS 16.2, *), let self else { result(false); return }
        let bridge = self.systemNavigation as? SystemNavigationBridge ?? SystemNavigationBridge()
        self.systemNavigation = bridge
        bridge.handle(call, result: result)
      }
    }
    FlutterMethodChannel(
      name: "waybi/navigation_audio",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      let session = AVAudioSession.sharedInstance()
      do {
        switch call.method {
        case "prepare":
          try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
          try session.setActive(true)
        case "release":
          try session.setActive(false, options: .notifyOthersOnDeactivation)
        default:
          result(FlutterMethodNotImplemented)
          return
        }
        result(nil)
      } catch {
        result(FlutterError(code: "navigation_audio", message: error.localizedDescription, details: nil))
      }
    }
    FlutterMethodChannel(
      name: "waybi/navigation_camera",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "pauseFollowing" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        func pause(_ view: UIView) {
          if let map = view as? GMSMapView { map.cameraMode = .free }
          view.subviews.forEach(pause)
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        if let view = self?.window?.rootViewController?.view ?? windows.first(where: { $0.isKeyWindow })?.rootViewController?.view {
          pause(view)
        }
        result(nil)
      }
    }
    FlutterMethodChannel(
      name: "waybi/map_language",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      if call.method == "setLanguage" {
        // Native Google maps use the system's per-app language. There is no
        // supported runtime SDK language setter on iOS.
        let language = call.arguments as? String ?? "en"
        let native = Bundle.main.preferredLocalizations.first ?? "en"
        result(native.hasPrefix(language))
      } else if call.method == "openSettings",
                let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(
      name: "waybi/device_heading",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setStreamHandler(headingHandler)
    FlutterMethodChannel(
      name: "waybi/share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareText",
            let arguments = call.arguments as? [String: Any],
            let text = arguments["text"] as? String,
            !text.isEmpty else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        guard let root = self?.window?.rootViewController ??
          (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
          result(FlutterError(code: "NO_WINDOW", message: "No active iOS window", details: nil))
          return
        }
        let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
          popover.sourceView = root.view
          popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
        }
        (root.presentedViewController ?? root).present(share, animated: true)
        result(nil)
      }
    }
  }
}

private final class WaybiGooglePlacePicker: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
  private let url: URL
  private var completion: ((String?) -> Void)?
  private var web: WKWebView?
  init(url: URL, completion: @escaping (String?) -> Void) {
    self.url = url; self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("Use the search URL initializer") }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Waybi"
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closePicker))
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.userContentController.add(self, name: "waybiPlaces")
    let web = WKWebView(frame: .zero, configuration: config)
    self.web = web; web.navigationDelegate = self; web.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(web)
    NSLayoutConstraint.activate([
      web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    ])
    web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
  }
  @objc private func closePicker() { finish(nil) }
  private func finish(_ value: String?) {
    guard let completion else { return }
    self.completion = nil
    web?.stopLoading(); web?.configuration.userContentController.removeScriptMessageHandler(forName: "waybiPlaces")
    dismiss(animated: true) { completion(value) }
  }
  private func fallback() {
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
    let data = try? JSONSerialization.data(withJSONObject: ["status": "fallback", "query": query])
    finish(data.flatMap { String(data: $0, encoding: .utf8) })
  }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https",
          message.frameInfo.securityOrigin.host == "waybi.co", let body = message.body as? String,
          body.utf8.count < 4096 else { return }
    finish(body)
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fallback() }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fallback() }
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard navigationAction.targetFrame?.isMainFrame != false, let next = navigationAction.request.url else { decisionHandler(.allow); return }
    if next.scheme == "https" && next.host == "waybi.co" && next.path == "/api/search/google" { decisionHandler(.allow) }
    else { decisionHandler(.cancel); if next.scheme == "https" { UIApplication.shared.open(next) } }
  }
}

// Core Location heading follows the physical top of the iPhone, unlike GPS course.
private final class DeviceHeadingStreamHandler: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  private let locationManager = CLLocationManager()
  private var sink: FlutterEventSink?

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.headingOrientation = .portrait
    locationManager.headingFilter = 2
    locationManager.distanceFilter = 25
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    guard CLLocationManager.headingAvailable() else { return nil }
    // True north is available only while this manager also receives locations.
    if locationManager.authorizationStatus == .authorizedWhenInUse ||
       locationManager.authorizationStatus == .authorizedAlways {
      locationManager.startUpdatingLocation()
      locationManager.startUpdatingHeading()
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    locationManager.stopUpdatingHeading()
    locationManager.stopUpdatingLocation()
    sink = nil
    return nil
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if sink != nil && (manager.authorizationStatus == .authorizedWhenInUse ||
                       manager.authorizationStatus == .authorizedAlways) && CLLocationManager.headingAvailable() {
      manager.startUpdatingLocation()
      manager.startUpdatingHeading()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
    guard heading.headingAccuracy >= 0, heading.trueHeading >= 0 else { return }
    sink?(["heading": heading.trueHeading, "accuracy": heading.headingAccuracy])
  }
}
