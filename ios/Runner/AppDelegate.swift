import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IncomingFilesPlugin") {
      IncomingFilesPlugin.register(with: registrar)
    }
  }
}

/// Primește fișierele trimise către Notițe din meniul de partajare
/// („Deschide în Notițe” / „Copiază în Notițe”), atât când aplicația e
/// închisă, cât și când rulează. Fiecare fișier e copiat într-un folder
/// temporar, iar căile ajung în Flutter pe canalul `notite/incoming_files`.
class IncomingFilesPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let channel: FlutterMethodChannel
  private var pending: [String] = []

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "notite/incoming_files", binaryMessenger: registrar.messenger())
    let instance = IncomingFilesPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    if #available(iOS 13.0, *) {
      registrar.addSceneDelegate(instance)
    }
  }

  // Flutter cere fișierele primite (la pornire și după fiecare notificare).
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "takePending" {
      result(pending)
      pending.removeAll()
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  // Aplicația era închisă: fișierul vine odată cu conectarea scenei.
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts, !contexts.isEmpty else {
      return false
    }
    return receive(contexts.map { $0.url })
  }

  // Aplicația rula deja.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    return receive(URLContexts.map { $0.url })
  }

  // Varianta fără scene (rezervă).
  func application(
    _ application: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return receive([url])
  }

  private func receive(_ urls: [URL]) -> Bool {
    let fileUrls = urls.filter { $0.isFileURL }
    guard !fileUrls.isEmpty else { return false }
    let fm = FileManager.default
    for url in fileUrls {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let dir = fm.temporaryDirectory
        .appendingPathComponent("incoming", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        try fm.copyItem(at: url, to: dest)
        pending.append(dest.path)
        // Copia din „Inbox” făcută de iOS nu mai e necesară.
        if url.path.contains("/Inbox/") { try? fm.removeItem(at: url) }
      } catch {
        NSLog("Notite: nu am putut primi fișierul \(url.lastPathComponent): \(error)")
      }
    }
    channel.invokeMethod("filesReceived", arguments: nil)
    return true
  }
}
