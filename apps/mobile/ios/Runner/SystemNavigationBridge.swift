import ActivityKit
import Flutter
import UIKit

@available(iOS 16.2, *)
@MainActor
final class SystemNavigationBridge {
  private var activity: Activity<NavigationAttributes>?

  private func content(_ args: [String: Any]) -> ActivityContent<NavigationAttributes.ContentState> {
    let now = Date()
    return ActivityContent(state: .init(
      instruction: args["instruction"] as? String ?? "",
      distance: args["distance"] as? String ?? "—",
      remaining: args["remaining"] as? String ?? "—",
      arrival: now.addingTimeInterval(Double(args["seconds"] as? Int ?? 0)),
      maneuver: args["maneuver"] as? String ?? "arrow.up",
      offRoute: args["offRoute"] as? Bool ?? false,
      updatedAt: now
    ), staleDate: now.addingTimeInterval(45))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    Task { @MainActor in
      switch call.method {
      case "start":
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else {
          result(false)
          return
        }
        // Clean up a stale surface left by a terminated previous trip.
        for previous in Activity<NavigationAttributes>.activities {
          await previous.end(nil, dismissalPolicy: .immediate)
        }
        do {
          activity = try Activity.request(
            attributes: NavigationAttributes(
              destination: args["destination"] as? String ?? "Waybi",
              language: args["language"] as? String ?? "en"
            ), content: content(args), pushType: nil
          )
          result(true)
        } catch {
          result(FlutterError(code: "LIVE_ACTIVITY_UNAVAILABLE", message: "Live Activity could not start", details: nil))
        }
      case "update":
        guard let activity else { result(false); return }
        await activity.update(content(args))
        result(true)
      case "stop":
        for previous in Activity<NavigationAttributes>.activities {
          await previous.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
