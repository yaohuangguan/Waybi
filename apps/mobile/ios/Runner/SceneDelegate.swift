import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      ExternalNavigationBridge.shared.receive(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let unrelated = URLContexts.filter { !ExternalNavigationBridge.shared.receive($0.url) }
    if !unrelated.isEmpty { super.scene(scene, openURLContexts: Set(unrelated)) }
  }
}
