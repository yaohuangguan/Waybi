// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "WaybiNavigationCore",
  platforms: [.macOS(.v13)],
  products: [.library(name: "WaybiNavigationCore", targets: ["WaybiNavigationCore"])],
  targets: [
    .target(name: "WaybiNavigationCore", path: "Runner",
      exclude: ["AppDelegate.swift", "SceneDelegate.swift", "SystemNavigationBridge.swift",
        "Assets.xcassets", "Base.lproj", "Info.plist", "Runner-Bridging-Header.h",
        "Runner.entitlements", "Navigation.entitlements", "PrivacyInfo.xcprivacy",
        "GeneratedPluginRegistrant.h", "GeneratedPluginRegistrant.m"],
      sources: ["ExternalNavigationBridge.swift"]),
    .testTarget(name: "WaybiNavigationCoreTests", dependencies: ["WaybiNavigationCore"],
      path: "NativeTests")
  ]
)
