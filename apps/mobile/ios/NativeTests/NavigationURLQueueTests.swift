import XCTest
@testable import WaybiNavigationCore

final class NavigationURLQueueTests: XCTestCase {
  func testOAuthAndWebURLsAreNotClaimedOrAllowedToOverwriteNavigation() {
    var queue = NavigationURLQueue()
    let accepted = URL(string: "waybi://navigate?destination=Airport")!
    XCTAssertEqual(queue.receive(accepted), .queued)
    for value in ["https://waybi.co", "com.google.oauth://callback", "other://navigate"] {
      XCTAssertEqual(queue.receive(URL(string: value)!), .unhandled)
      XCTAssertEqual(queue.pending, accepted.absoluteString)
    }
  }

  func testRequestReceivedBeforeFlutterIsDeliveredExactlyOnce() {
    var queue = NavigationURLQueue()
    let url = URL(string: "geo-navigation:///?destination=-36.8,174.7")!
    XCTAssertEqual(queue.receive(url), .queued)
    XCTAssertEqual(queue.takePending(), url.absoluteString)
    XCTAssertNil(queue.takePending())
  }

  func testLaunchNotificationsAreDeduplicatedWithoutRequeuingConsumedRequests() {
    var queue = NavigationURLQueue()
    let url = URL(string: "waybi://navigate?destination=Airport")!
    let now = Date(timeIntervalSince1970: 100)
    XCTAssertEqual(queue.receive(url, now: now), .queued)
    XCTAssertNotNil(queue.takePending())
    XCTAssertEqual(queue.receive(url, now: now.addingTimeInterval(0.49)), .duplicate)
    XCTAssertNil(queue.pending)
    XCTAssertEqual(queue.receive(url, now: now.addingTimeInterval(0.5)), .queued)
  }

  func testLatestDifferentDestinationWinsAndSchemeIsCaseInsensitive() {
    var queue = NavigationURLQueue()
    let now = Date(timeIntervalSince1970: 100)
    let first = URL(string: "WAYBI://navigate?destination=Airport")!
    let second = URL(string: "waybi://navigate?destination=8%20Whitaker%20Place")!
    XCTAssertEqual(queue.receive(first, now: now), .queued)
    XCTAssertEqual(queue.receive(second, now: now), .queued)
    XCTAssertEqual(queue.takePending(), second.absoluteString)
  }

  func testEscapedDestinationIsPreservedWithoutInterpretingItAsAnotherRequest() {
    var queue = NavigationURLQueue()
    var components = URLComponents()
    components.scheme = "waybi"
    components.host = "navigate"
    components.queryItems = [URLQueryItem(name: "destination", value: "机场 & home?x=1#楼层")]
    let url = components.url!
    XCTAssertEqual(queue.receive(url), .queued)
    XCTAssertEqual(queue.takePending(), url.absoluteString)
  }
}
