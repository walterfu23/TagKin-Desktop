import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// Security-scoped bookmarks for sandboxed local folder access (D3/D8).
///
/// Channel: `tagkin_desktop/security_scoped_bookmarks`
/// Methods:
/// - pickFolder → { path, bookmarkBase64 } | null (cancel)
/// - pickSaveFile → { path } | null (cancel); retains the panel URL
/// - installSaveFile(sourcePath) → byte count
/// - releaseSaveFile → null
/// - startAccess(bookmarkBase64) → resolved path
/// - stopAccess(bookmarkBase64) → null
enum SecurityScopedBookmarksPlugin {
  static let channelName = "tagkin_desktop/security_scoped_bookmarks"

  /// Retains URLs with an active startAccessingSecurityScopedResource call.
  private static var active: [String: URL] = [:]
  /// One-shot NSSavePanel destination (not bookmarkable until the file exists).
  private static var pendingSave: URL?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "pickFolder":
        pickFolder(result: result)
      case "pickSaveFile":
        let args = call.arguments as? [String: Any]
        pickSaveFile(
          fileName: args?["fileName"] as? String ?? "item-list.mp4",
          fileExtension: args?["fileExtension"] as? String ?? "mp4",
          result: result
        )
      case "installSaveFile":
        guard let source = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "sourcePath required", details: nil))
          return
        }
        installSaveFile(sourcePath: source, result: result)
      case "releaseSaveFile":
        releaseSaveFile(result: result)
      case "startAccess":
        guard let bookmark = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "bookmarkBase64 required", details: nil))
          return
        }
        startAccess(bookmarkBase64: bookmark, result: result)
      case "stopAccess":
        guard let bookmark = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "bookmarkBase64 required", details: nil))
          return
        }
        stopAccess(bookmarkBase64: bookmark, result: result)
      case "createBookmark":
        guard let path = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "path required", details: nil))
          return
        }
        createBookmark(path: path, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func pickFolder(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = "Select Folder"

    let response = panel.runModal()
    guard response == .OK, let url = panel.url else {
      result(nil)
      return
    }

    do {
      let data = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      let b64 = data.base64EncodedString()
      result(["path": url.path, "bookmarkBase64": b64])
    } catch {
      result(FlutterError(
        code: "bookmark_create_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private static func pickSaveFile(
    fileName: String,
    fileExtension: String,
    result: @escaping FlutterResult
  ) {
    releasePendingSave()
    let panel = NSSavePanel()
    panel.title = "Export item list"
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = fileName
    if let type = UTType(filenameExtension: fileExtension) {
      panel.allowedContentTypes = [type]
    }

    let response = panel.runModal()
    guard response == .OK, let url = panel.url else {
      result(nil)
      return
    }

    _ = url.startAccessingSecurityScopedResource()
    pendingSave = url
    result(["path": url.path])
  }

  private static func installSaveFile(
    sourcePath: String,
    result: @escaping FlutterResult
  ) {
    guard let dest = pendingSave else {
      result(FlutterError(
        code: "no_save",
        message: "Save As is not open",
        details: nil
      ))
      return
    }
    let source = URL(fileURLWithPath: sourcePath)
    let fm = FileManager.default
    do {
      if fm.fileExists(atPath: dest.path) {
        try fm.removeItem(at: dest)
      }
      try fm.copyItem(at: source, to: dest)
      let attrs = try fm.attributesOfItem(atPath: dest.path)
      let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
      if size == 0 {
        result(FlutterError(
          code: "empty_export",
          message: "The exported file was empty",
          details: nil
        ))
        return
      }
      result(size)
    } catch {
      result(FlutterError(
        code: "install_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private static func releaseSaveFile(result: @escaping FlutterResult) {
    releasePendingSave()
    result(nil)
  }

  private static func releasePendingSave() {
    if let url = pendingSave {
      url.stopAccessingSecurityScopedResource()
    }
    pendingSave = nil
  }

  private static func createBookmark(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    do {
      let data = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      result(data.base64EncodedString())
    } catch {
      result(FlutterError(
        code: "bookmark_create_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private static func startAccess(bookmarkBase64: String, result: @escaping FlutterResult) {
    if let existing = active[bookmarkBase64] {
      result(existing.path)
      return
    }
    guard let data = Data(base64Encoded: bookmarkBase64) else {
      result(FlutterError(code: "bad_bookmark", message: "invalid base64", details: nil))
      return
    }
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(
          code: "access_denied",
          message: "startAccessingSecurityScopedResource failed",
          details: nil
        ))
        return
      }
      active[bookmarkBase64] = url
      result(url.path)
    } catch {
      result(FlutterError(
        code: "bookmark_resolve_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private static func stopAccess(bookmarkBase64: String, result: @escaping FlutterResult) {
    if let url = active.removeValue(forKey: bookmarkBase64) {
      url.stopAccessingSecurityScopedResource()
    }
    result(nil)
  }
}
