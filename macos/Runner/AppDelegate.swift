import Cocoa
import FlutterMacOS
import app_links

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    applyDisplayName()
  }

  /// Safari’s “Allow this website to open TagKin.app?” uses Launch Services
  /// `application:openURLs:`, not the legacy `kAEGetURL` Apple Event that
  /// `app_links` registers. Without this forward, Allow brings the app forward
  /// and drops the `tagkindesktop://oauth/callback` Clerk needs to finish Google.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      AppLinks.shared.handleLink(link: url.absoluteString)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// MainMenu.xib ships with the placeholder "APP_NAME"; Xcode does not
  /// substitute PRODUCT_NAME into the compiled nib. Replace it with the
  /// user-facing display name from Info.plist (PRODUCT_DISPLAY_NAME).
  private func applyDisplayName() {
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "TagKin"
    guard let appItem = NSApp.mainMenu?.items.first else { return }
    appItem.title = name
    guard let submenu = appItem.submenu else { return }
    submenu.title = name
    for item in submenu.items {
      if item.title.contains("APP_NAME") {
        item.title = item.title.replacingOccurrences(of: "APP_NAME", with: name)
      }
    }
    for window in NSApp.windows where window.title.contains("APP_NAME") {
      window.title = name
    }
  }
}
