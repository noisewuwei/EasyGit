import Cocoa
import FlutterMacOS

import desktop_multi_window
import file_selector_macos
import screen_retriever
import shared_preferences_foundation
import window_manager

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      FileSelectorPlugin.register(with: controller.engine.registrar(forPlugin: "FileSelectorPlugin"))
      ScreenRetrieverPlugin.register(with: controller.engine.registrar(forPlugin: "ScreenRetrieverPlugin"))
      SharedPreferencesPlugin.register(with: controller.engine.registrar(forPlugin: "SharedPreferencesPlugin"))
      WindowManagerPlugin.register(with: controller.engine.registrar(forPlugin: "WindowManagerPlugin"))
    };
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
