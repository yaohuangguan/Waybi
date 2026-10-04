import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WaybiNavigationBundle: WidgetBundle {
  var body: some Widget { WaybiNavigationLiveActivity() }
}

struct WaybiNavigationLiveActivity: Widget {
  private let lime = Color(red: 0.66, green: 0.85, blue: 0.42)
  private let ink = Color(red: 0.12, green: 0.18, blue: 0.14)

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: NavigationAttributes.self) { context in
      HStack(spacing: 14) {
        Image(systemName: context.isStale || context.state.gpsReliable == false ? "location.slash" : context.state.maneuver)
          .font(.system(size: 32, weight: .bold)).foregroundStyle(lime)
        VStack(alignment: .leading, spacing: 5) {
          Text(context.isStale || context.state.gpsReliable == false ? "GPS" : context.state.distance).font(.title2.bold()).foregroundStyle(lime)
          Text((context.isStale || context.state.gpsReliable == false) ? waiting(context) : context.state.instruction)
            .font(.subheadline.weight(.semibold)).lineLimit(2)
          Text(context.attributes.destination).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
        }
        Spacer(minLength: 2)
        VStack(spacing: 6) {
          Image("WaybiBird").resizable().scaledToFit().frame(width: 38, height: 38).clipShape(Circle())
          Text(context.state.arrival, style: .time).font(.caption.bold())
          Text(context.state.remaining).font(.caption2)
        }
      }
      .padding(16).foregroundStyle(.white)
      .activityBackgroundTint(ink).activitySystemActionForegroundColor(lime)
      .widgetURL(URL(string: "waybi://navigation"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: context.isStale || context.state.gpsReliable == false ? "location.slash" : context.state.maneuver).font(.title).foregroundStyle(lime)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.isStale || context.state.gpsReliable == false ? "GPS" : context.state.distance).font(.title3.bold()).foregroundStyle(lime)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.attributes.destination).font(.caption.weight(.semibold)).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 6) {
            Text((context.isStale || context.state.gpsReliable == false) ? waiting(context) : context.state.instruction)
              .font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack {
              Text(context.state.remaining)
              Spacer()
              Image("WaybiBird").resizable().scaledToFit().frame(width: 20, height: 20).clipShape(Circle())
              Text(context.state.arrival, style: .time)
            }.font(.caption).foregroundStyle(lime)
          }
        }
      } compactLeading: {
        Image(systemName: context.isStale || context.state.gpsReliable == false ? "location.slash" : context.state.maneuver).foregroundStyle(lime)
      } compactTrailing: {
        Text((context.isStale || context.state.gpsReliable == false) ? "GPS" : context.state.distance).font(.caption2.bold()).foregroundStyle(lime)
      } minimal: {
        Image(systemName: (context.isStale || context.state.gpsReliable == false) ? "location.slash" : context.state.maneuver).foregroundStyle(lime)
      }
      .widgetURL(URL(string: "waybi://navigation"))
      .keylineTint(lime)
    }
  }

  private func waiting(_ context: ActivityViewContext<NavigationAttributes>) -> String {
    context.attributes.language == "zh" ? "等待定位更新" : "Waiting for location update"
  }
}
