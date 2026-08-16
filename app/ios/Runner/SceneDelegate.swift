import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    var handled = false
    for context in URLContexts {
      handled = HearthBitFileImportBridge.shared.accept(context.url) || handled
    }
    if !handled {
      super.scene(scene, openURLContexts: URLContexts)
    }
  }
}
