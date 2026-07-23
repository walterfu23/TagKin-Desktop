import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Wide library table: keep the window usable when resized.
    self.minSize = NSSize(width: 1200, height: 700)

    RegisterGeneratedPlugins(registry: flutterViewController)
    SecurityScopedBookmarksPlugin.register(
      with: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}
