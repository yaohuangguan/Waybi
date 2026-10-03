import ActivityKit
import Flutter
import UIKit

@available(iOS 16.2, *)
@MainActor
final class SystemNavigationBridge {
  private var activity: Activity<NavigationAttributes>?
  private var desired: [String: Any]?
  private var generation = 0
  private var creating = false
  private var dismissed = false
  private var lastError: String?
  private var observers: [NSObjectProtocol] = []

  init() {
    for name in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in await self?.ensureActivity() }
      })
    }
  }

  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  private var foreground: Bool {
    UIApplication.shared.applicationState == .active ||
      UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
  }

  private var status: [String: Any] {
    let state = activity?.activityState
    return ["supported": true,
      "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
      "active": state == .active || state == .stale,
      "pending": desired != nil && activity == nil && !dismissed,
      "errorCode": lastError as Any? ?? NSNull(),
      "activityState": state.map { String(describing: $0) } ?? "none"]
  }

  private func content(_ args: [String: Any]) -> ActivityContent<NavigationAttributes.ContentState> {
    let now = Date()
    return ActivityContent(state: .init(
      instruction: args["instruction"] as? String ?? "",
      distance: args["distance"] as? String ?? "—",
      remaining: args["remaining"] as? String ?? "—",
      arrival: now.addingTimeInterval(Double(args["seconds"] as? Int ?? 0)),
      maneuver: args["maneuver"] as? String ?? "arrow.up",
      offRoute: args["offRoute"] as? Bool ?? false,
      updatedAt: now,
      gpsReliable: args["gpsReliable"] as? Bool ?? true
    ), staleDate: now.addingTimeInterval(15), relevanceScore: 100)
  }

  private func ensureActivity() async {
    guard let args = desired, !dismissed else { return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      lastError = "LIVE_ACTIVITIES_DISABLED"
      return
    }
    if let current = activity {
      if current.activityState == .dismissed {
        dismissed = true
        lastError = "LIVE_ACTIVITY_DISMISSED"
        return
      }
      if current.activityState == .active || current.activityState == .stale {
        await current.update(content(args))
        return
      }
      activity = nil
    }
    // Starting is foreground-only. Preserve the trip if the person switches
    // apps during startup, then recover when its scene becomes active again.
    guard foreground, !creating else { return }
    creating = true
    defer { creating = false }
    let session = generation
    for previous in Activity<NavigationAttributes>.activities {
      await previous.end(nil, dismissalPolicy: .immediate)
      guard session == generation, desired != nil else { return }
    }
    guard session == generation, foreground, let latest = desired else { return }
    do {
      activity = try Activity.request(
        attributes: NavigationAttributes(destination: latest["destination"] as? String ?? "Waybi",
          language: latest["language"] as? String ?? "en"),
        content: content(latest), pushType: nil)
      lastError = nil
      NSLog("Waybi Live Activity started")
    } catch {
      lastError = "LIVE_ACTIVITY_UNAVAILABLE"
      NSLog("Waybi Live Activity start failed: %@", String(describing: error))
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    Task { @MainActor in
      switch call.method {
      case "start":
        generation += 1
        let session = generation
        desired = args
        dismissed = false
        lastError = nil
        for previous in Activity<NavigationAttributes>.activities {
          await previous.end(nil, dismissalPolicy: .immediate)
          guard session == generation else { result(status); return }
        }
        activity = nil
        await ensureActivity()
        result(status)
      case "update":
        guard desired != nil else { result(status); return }
        desired = args
        await ensureActivity()
        result(status)
      case "status":
        result(status)
      case "stop":
        generation += 1
        desired = nil
        dismissed = false
        lastError = nil
        for previous in Activity<NavigationAttributes>.activities {
          await previous.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        result(status)
      case "openSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
