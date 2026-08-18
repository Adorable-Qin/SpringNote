import Cocoa
import FlutterMacOS
import Carbon.HIToolbox
import ServiceManagement

private func boolValue(_ arguments: [String: Any], _ key: String, fallback: Bool = false) -> Bool {
  arguments[key] as? Bool ?? fallback
}

private func intValue(_ arguments: [String: Any], _ key: String, fallback: Int = 0) -> Int {
  if let value = arguments[key] as? Int {
    return value
  }
  if let value = arguments[key] as? Int64 {
    return Int(value)
  }
  if let value = arguments[key] as? Double {
    return Int(value)
  }
  return fallback
}

private func doubleValue(_ arguments: [String: Any], _ key: String, fallback: Double = 0) -> Double {
  if let value = arguments[key] as? Double {
    return value
  }
  if let value = arguments[key] as? Int {
    return Double(value)
  }
  if let value = arguments[key] as? Int64 {
    return Double(value)
  }
  return fallback
}

private func stringValue(_ arguments: [String: Any], _ key: String, fallback: String = "") -> String {
  arguments[key] as? String ?? fallback
}

private func stringMapValue(_ arguments: [String: Any], _ key: String) -> [String: Any]? {
  arguments[key] as? [String: Any]
}

final class ClipboardImageController {
  private let allowedImageExtensions: Set<String> = [
    "png",
    "jpg",
    "jpeg",
    "gif",
    "webp",
    "bmp",
    "heic",
    "svg",
    "jfif",
  ]

  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "spring_note/clipboard_image",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "readImageFiles":
      result(readImageFiles())
    case "readPngImage":
      result(readPngImage())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func readImageFiles() -> [String] {
    let pasteboard = NSPasteboard.general
    var paths: [String] = []

    if let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] {
      for url in urls {
        appendImageFile(url.path, to: &paths)
      }
    }

    let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    if let filenames = pasteboard.propertyList(forType: filenamesType) as? [String] {
      for path in filenames {
        appendImageFile(path, to: &paths)
      }
    }

    return paths
  }

  private func appendImageFile(_ path: String, to paths: inout [String]) {
    let url = URL(fileURLWithPath: path)
    let ext = url.pathExtension.lowercased()
    guard allowedImageExtensions.contains(ext) else {
      return
    }
    guard FileManager.default.fileExists(atPath: path) else {
      return
    }
    if !paths.contains(path) {
      paths.append(path)
    }
  }

  private func readPngImage() -> FlutterStandardTypedData? {
    let pasteboard = NSPasteboard.general
    if let data = pasteboard.data(forType: .png), !data.isEmpty {
      return FlutterStandardTypedData(bytes: data)
    }
    if let data = pasteboard.data(forType: .tiff),
       let image = NSImage(data: data),
       let pngData = pngData(from: image) {
      return FlutterStandardTypedData(bytes: pngData)
    }
    if let image = NSImage(pasteboard: pasteboard),
       let pngData = pngData(from: image) {
      return FlutterStandardTypedData(bytes: pngData)
    }
    return nil
  }

  private func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
      return nil
    }
    return bitmap.representation(using: .png, properties: [:])
  }
}

final class TrayController: NSObject {
  private var statusItem: NSStatusItem?
  private var channel: FlutterMethodChannel?
  private weak var window: NSWindow?
  private var closeToTray = false
  private var exiting = false

  var shouldCloseToTray: Bool {
    statusItem != nil && closeToTray && !exiting
  }

  func attach(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(
      name: "spring_note/tray",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func dispose() {
    hideStatusItem()
    closeToTray = false
  }

  func showMainWindow() {
    guard let window else {
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func hideMainWindow() {
    window?.orderOut(nil)
  }

  func prepareForApplicationExit() {
    exiting = true
    closeToTray = false
    hideStatusItem()
  }

  func exitApplication() {
    prepareForApplicationExit()
    NSApp.terminate(nil)
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "configure":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "configure expects a map", details: nil))
        return
      }
      let showTrayIcon = arguments["showTrayIcon"] as? Bool ?? false
      let nextCloseToTray = arguments["closeToTray"] as? Bool ?? false
      configure(showTrayIcon: showTrayIcon, closeToTray: nextCloseToTray)
      result(nil)
    case "dispose":
      dispose()
      result(nil)
    case "prepareForApplicationExit":
      prepareForApplicationExit()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configure(showTrayIcon: Bool, closeToTray: Bool) {
    self.closeToTray = showTrayIcon && closeToTray
    if showTrayIcon {
      showStatusItem()
    } else {
      hideStatusItem()
    }
  }

  private func showStatusItem() {
    if statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      item.button?.target = self
      item.button?.action = #selector(statusItemClicked(_:))
      item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
      statusItem = item
    }

    if let image = loadStatusIcon() {
      statusItem?.button?.image = image
    } else {
      statusItem?.button?.title = "S"
    }
    statusItem?.button?.toolTip = "SpringNote-Agenda"
  }

  private func loadStatusIcon() -> NSImage? {
    guard let image = NSImage(named: "TrayIcon") else {
      return nil
    }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = false
    return image
  }

  private func hideStatusItem() {
    guard let item = statusItem else {
      return
    }
    NSStatusBar.system.removeStatusItem(item)
    statusItem = nil
  }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(
        title: "打开 SpringNote-Agenda",
        action: #selector(openMenuItemClicked(_:)),
        keyEquivalent: ""
      )
    )
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(
        title: "退出",
        action: #selector(exitMenuItemClicked(_:)),
        keyEquivalent: "q"
      )
    )
    menu.items.forEach { $0.target = self }
    return menu
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else {
      showMainWindow()
      return
    }
    if event.type == .rightMouseUp {
      buildMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    } else if event.type == .leftMouseUp {
      showMainWindow()
    }
  }

  @objc private func openMenuItemClicked(_ sender: NSMenuItem) {
    showMainWindow()
  }

  @objc private func exitMenuItemClicked(_ sender: NSMenuItem) {
    exitApplication()
  }
}

final class AutoStartController: NSObject {
  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "spring_note/auto_start",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "setEnabled":
      guard let enabled = call.arguments as? Bool else {
        result(FlutterError(code: "bad_args", message: "setEnabled expects a bool", details: nil))
        return
      }
      result(setEnabled(enabled))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setEnabled(_ enabled: Bool) -> Bool {
    guard #available(macOS 13.0, *) else {
      return false
    }

    let service = SMAppService.mainApp
    do {
      if enabled {
        if service.status == .enabled || service.status == .requiresApproval {
          return true
        }
        try service.register()
        return service.status == .enabled || service.status == .requiresApproval
      }

      if service.status == .notRegistered || service.status == .notFound {
        return true
      }
      try service.unregister()
      return service.status == .notRegistered || service.status == .notFound
    } catch {
      return false
    }
  }
}

final class SecurityScopedDirectoryController: NSObject {
  private let defaultsKey = "spring_note.security_scoped_directory_bookmarks"
  private var channel: FlutterMethodChannel?
  private var activeUrls: [String: URL] = [:]

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "spring_note/security_scoped_directories",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "saveBookmark":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "saveBookmark expects a path", details: nil))
        return
      }
      result(saveBookmark(path: path))
    case "startAccessing":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "startAccessing expects a path", details: nil))
        return
      }
      result(startAccessing(path: path))
    case "removeBookmark":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "removeBookmark expects a path", details: nil))
        return
      }
      removeBookmark(path: path)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func saveBookmark(path: String) -> Bool {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    do {
      let bookmark = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var bookmarks = storedBookmarks()
      bookmarks[normalizedPath(path)] = bookmark.base64EncodedString()
      UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
      _ = startAccessing(path: path)
      return true
    } catch {
      return false
    }
  }

  private func startAccessing(path: String) -> Bool {
    let key = normalizedPath(path)
    if activeUrls[key] != nil {
      return true
    }

    guard
      let bookmarkString = storedBookmarks()[key],
      let bookmark = Data(base64Encoded: bookmarkString)
    else {
      return false
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      if isStale {
        _ = saveBookmark(path: url.path)
      }
      if url.startAccessingSecurityScopedResource() {
        activeUrls[key] = url
        return true
      }
      return false
    } catch {
      return false
    }
  }

  private func removeBookmark(path: String) {
    let key = normalizedPath(path)
    if let url = activeUrls.removeValue(forKey: key) {
      url.stopAccessingSecurityScopedResource()
    }
    var bookmarks = storedBookmarks()
    bookmarks.removeValue(forKey: key)
    UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
  }

  private func storedBookmarks() -> [String: String] {
    UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
  }

  private func normalizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }
}

final class GlobalHotkeyController: NSObject {
  private var channel: FlutterMethodChannel?
  private weak var mainWindow: NSWindow?
  private var hotkeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private let hotkeyId = EventHotKeyID(signature: fourCharCode("SPNT"), id: 1)

  func attach(mainWindow: NSWindow, messenger: FlutterBinaryMessenger) {
    self.mainWindow = mainWindow
    channel = FlutterMethodChannel(
      name: "spring_note/global_hotkeys",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    installEventHandlerIfNeeded()
  }

  deinit {
    unregisterToggleWindowHotkey()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "setToggleWindowHotkey":
      guard let hotkey = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "setToggleWindowHotkey expects a string", details: nil))
        return
      }
      result(setToggleWindowHotkey(hotkey))
    case "unregisterToggleWindowHotkey":
      unregisterToggleWindowHotkey()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installEventHandlerIfNeeded() {
    guard eventHandler == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let selfPointer = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard
          let event,
          let userData
        else {
          return noErr
        }

        var eventHotkeyId = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &eventHotkeyId
        )
        guard status == noErr else {
          return status
        }

        let controller = Unmanaged<GlobalHotkeyController>
          .fromOpaque(userData)
          .takeUnretainedValue()
        if eventHotkeyId.signature == controller.hotkeyId.signature &&
          eventHotkeyId.id == controller.hotkeyId.id {
          controller.toggleMainWindow()
        }
        return noErr
      },
      1,
      &eventType,
      selfPointer,
      &eventHandler
    )
  }

  private func setToggleWindowHotkey(_ hotkey: String) -> Bool {
    guard let spec = parseHotkey(hotkey) else {
      return false
    }

    unregisterToggleWindowHotkey()
    let status = RegisterEventHotKey(
      UInt32(spec.keyCode),
      spec.modifiers,
      hotkeyId,
      GetApplicationEventTarget(),
      0,
      &hotkeyRef
    )
    return status == noErr
  }

  private func unregisterToggleWindowHotkey() {
    guard let hotkeyRef else {
      return
    }
    UnregisterEventHotKey(hotkeyRef)
    self.hotkeyRef = nil
  }

  private func toggleMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    guard let window = mainWindow else {
      return
    }

    if !window.isVisible || window.isMiniaturized {
      window.makeKeyAndOrderFront(nil)
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      return
    }

    window.orderOut(nil)
  }

  private func parseHotkey(_ hotkey: String) -> (keyCode: UInt16, modifiers: UInt32)? {
    let tokens = hotkey
      .split(separator: "+")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
      .filter { !$0.isEmpty }
    guard !tokens.isEmpty else {
      return nil
    }

    var modifiers: UInt32 = 0
    var keyCode: UInt16?

    for token in tokens {
      switch token {
      case "CTRL", "CONTROL":
        modifiers |= UInt32(controlKey)
      case "SHIFT":
        modifiers |= UInt32(shiftKey)
      case "ALT", "OPTION":
        modifiers |= UInt32(optionKey)
      case "WIN", "WINDOWS", "META", "CMD", "COMMAND", "SUPER":
        modifiers |= UInt32(cmdKey)
      default:
        guard keyCode == nil, let nextKeyCode = keyCodeForToken(token) else {
          return nil
        }
        keyCode = nextKeyCode
      }
    }

    guard let keyCode else {
      return nil
    }
    return (keyCode, modifiers)
  }

  private func keyCodeForToken(_ token: String) -> UInt16? {
    if token.count == 1, let scalar = token.unicodeScalars.first {
      switch scalar.value {
      case 65: return UInt16(kVK_ANSI_A)
      case 66: return UInt16(kVK_ANSI_B)
      case 67: return UInt16(kVK_ANSI_C)
      case 68: return UInt16(kVK_ANSI_D)
      case 69: return UInt16(kVK_ANSI_E)
      case 70: return UInt16(kVK_ANSI_F)
      case 71: return UInt16(kVK_ANSI_G)
      case 72: return UInt16(kVK_ANSI_H)
      case 73: return UInt16(kVK_ANSI_I)
      case 74: return UInt16(kVK_ANSI_J)
      case 75: return UInt16(kVK_ANSI_K)
      case 76: return UInt16(kVK_ANSI_L)
      case 77: return UInt16(kVK_ANSI_M)
      case 78: return UInt16(kVK_ANSI_N)
      case 79: return UInt16(kVK_ANSI_O)
      case 80: return UInt16(kVK_ANSI_P)
      case 81: return UInt16(kVK_ANSI_Q)
      case 82: return UInt16(kVK_ANSI_R)
      case 83: return UInt16(kVK_ANSI_S)
      case 84: return UInt16(kVK_ANSI_T)
      case 85: return UInt16(kVK_ANSI_U)
      case 86: return UInt16(kVK_ANSI_V)
      case 87: return UInt16(kVK_ANSI_W)
      case 88: return UInt16(kVK_ANSI_X)
      case 89: return UInt16(kVK_ANSI_Y)
      case 90: return UInt16(kVK_ANSI_Z)
      case 48: return UInt16(kVK_ANSI_0)
      case 49: return UInt16(kVK_ANSI_1)
      case 50: return UInt16(kVK_ANSI_2)
      case 51: return UInt16(kVK_ANSI_3)
      case 52: return UInt16(kVK_ANSI_4)
      case 53: return UInt16(kVK_ANSI_5)
      case 54: return UInt16(kVK_ANSI_6)
      case 55: return UInt16(kVK_ANSI_7)
      case 56: return UInt16(kVK_ANSI_8)
      case 57: return UInt16(kVK_ANSI_9)
      default: break
      }
    }

    if token.first == "F", let number = Int(token.dropFirst()) {
      switch number {
      case 1: return UInt16(kVK_F1)
      case 2: return UInt16(kVK_F2)
      case 3: return UInt16(kVK_F3)
      case 4: return UInt16(kVK_F4)
      case 5: return UInt16(kVK_F5)
      case 6: return UInt16(kVK_F6)
      case 7: return UInt16(kVK_F7)
      case 8: return UInt16(kVK_F8)
      case 9: return UInt16(kVK_F9)
      case 10: return UInt16(kVK_F10)
      case 11: return UInt16(kVK_F11)
      case 12: return UInt16(kVK_F12)
      case 13: return UInt16(kVK_F13)
      case 14: return UInt16(kVK_F14)
      case 15: return UInt16(kVK_F15)
      case 16: return UInt16(kVK_F16)
      case 17: return UInt16(kVK_F17)
      case 18: return UInt16(kVK_F18)
      case 19: return UInt16(kVK_F19)
      case 20: return UInt16(kVK_F20)
      default: break
      }
    }

    switch token {
    case "SPACE": return UInt16(kVK_Space)
    case "TAB": return UInt16(kVK_Tab)
    case "ENTER", "RETURN": return UInt16(kVK_Return)
    case "ESC", "ESCAPE": return UInt16(kVK_Escape)
    case "BACKSPACE": return UInt16(kVK_Delete)
    case "DELETE", "DEL": return UInt16(kVK_ForwardDelete)
    case "HOME": return UInt16(kVK_Home)
    case "END": return UInt16(kVK_End)
    case "PAGEUP", "PGUP": return UInt16(kVK_PageUp)
    case "PAGEDOWN", "PGDN": return UInt16(kVK_PageDown)
    case "UP": return UInt16(kVK_UpArrow)
    case "DOWN": return UInt16(kVK_DownArrow)
    case "LEFT": return UInt16(kVK_LeftArrow)
    case "RIGHT": return UInt16(kVK_RightArrow)
    default: return nil
    }
  }
}

private func fourCharCode(_ value: String) -> OSType {
  value.utf8.reduce(0) { result, byte in
    (result << 8) + OSType(byte)
  }
}
