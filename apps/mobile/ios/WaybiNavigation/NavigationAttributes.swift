import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct NavigationAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var instruction: String
    var distance: String
    var remaining: String
    var arrival: Date
    var maneuver: String
    var offRoute: Bool
    var updatedAt: Date
  }
  var destination: String
  var language: String
}
