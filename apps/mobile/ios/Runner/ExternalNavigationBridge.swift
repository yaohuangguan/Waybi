import AppIntents
import Flutter
import Foundation

/// Receives URLs before the Flutter engine is ready and wakes Dart to consume
/// the latest request. Only navigation schemes are claimed; OAuth goes to plugins.
final class ExternalNavigationBridge {
  static let shared = ExternalNavigationBridge()
  private var channel: FlutterMethodChannel?
  private var pending: String?
  private var lastURL: String?
  private var lastReceived = Date.distantPast

  @discardableResult
  func receive(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(),
          scheme == "waybi" || scheme == "geo-navigation" else { return false }
    let value = url.absoluteString
    // UIApplication and UIScene can report the same launch URL.
    if value == lastURL && Date().timeIntervalSince(lastReceived) < 0.5 { return true }
    lastURL = value
    lastReceived = Date()
    pending = value
    channel?.invokeMethod("pending", arguments: nil)
    return true
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "waybi/external_navigation", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takePending" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let value = self?.pending
      self?.pending = nil
      result(value)
    }
    if pending != nil { channel.invokeMethod("pending", arguments: nil) }
  }
}

@available(iOS 16.0, *)
struct NavigateWithWaybiIntent: AppIntent {
  static var title: LocalizedStringResource = "Navigate with Waybi"
  static var description = IntentDescription("Open a destination in Waybi and review the route before starting navigation.")
  // Retain the foreground behavior on iOS 16–25.
  static var openAppWhenRun: Bool = true
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }

  @Parameter(title: "Destination", description: "An address, place name, or latitude,longitude pair")
  var destination: String

  static var parameterSummary: some ParameterSummary {
    Summary("Navigate to \(\.$destination) with Waybi")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    let value = destination.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= 1000 else { throw NavigationIntentError.invalidDestination }
    var components = URLComponents()
    components.scheme = "waybi"
    components.host = "navigate"
    components.queryItems = [URLQueryItem(name: "destination", value: value)]
    guard let url = components.url else { throw NavigationIntentError.invalidDestination }
    ExternalNavigationBridge.shared.receive(url)
    return .result()
  }
}

@available(iOS 16.0, *)
private enum NavigationIntentError: Error, CustomLocalizedStringResourceConvertible {
  case invalidDestination
  var localizedStringResource: LocalizedStringResource { "Enter a destination address or coordinates." }
}

@available(iOS 16.0, *)
struct WaybiAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: NavigateWithWaybiIntent(),
      phrases: ["Navigate with \(.applicationName)", "Get directions with \(.applicationName)"],
      shortTitle: "Navigate with Waybi",
      systemImageName: "location.fill"
    )
  }
}
