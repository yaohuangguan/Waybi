import Flutter
import UIKit
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testNavigationURLsWaitForFlutterAndCannotConsumeOAuth() {
    var queue = NavigationURLQueue()
    let destination = URL(string: "waybi://navigate?destination=Airport")!
    XCTAssertEqual(queue.receive(destination), .queued)
    XCTAssertEqual(queue.receive(URL(string: "com.google.oauth://callback")!), .unhandled)
    XCTAssertEqual(queue.takePending(), destination.absoluteString)
    XCTAssertNil(queue.takePending())
  }

  func testDuplicateSceneAndApplicationNotificationsDoNotReopenNavigation() {
    var queue = NavigationURLQueue()
    let destination = URL(string: "geo-navigation:///?destination=-36.8,174.7")!
    let now = Date(timeIntervalSince1970: 100)
    XCTAssertEqual(queue.receive(destination, now: now), .queued)
    XCTAssertNotNil(queue.takePending())
    XCTAssertEqual(queue.receive(destination, now: now.addingTimeInterval(0.1)), .duplicate)
    XCTAssertNil(queue.pending)
  }
}
