import AuthenticationServices
import CryptoKit
import Flutter
import Speech
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechTranscriber") {
      SpeechTranscriber.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PrivacyShield") {
      PrivacyShield.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AutofillBridge") {
      AutofillBridge.register(with: registrar)
    }
  }
}

/// „Ascunde în comutatorul de aplicații”: cât timp aplicația nu e în
/// prim-plan, fereastra e acoperită de o estompare (canal `notite/privacy`).
/// Starea e ținută și în UserDefaults, ca să se aplice înainte de Flutter.
class PrivacyShield: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private static let key = "notite.hideInSwitcher"
  private static let tag = 0x4E6F_7465
  private var enabled: Bool {
    get { UserDefaults.standard.object(forKey: PrivacyShield.key) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: PrivacyShield.key) }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "notite/privacy", binaryMessenger: registrar.messenger())
    let instance = PrivacyShield()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    if #available(iOS 13.0, *) {
      registrar.addSceneDelegate(instance)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "setEnabled" {
      enabled = (call.arguments as? Bool) ?? true
      result(nil)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  func sceneWillResignActive(_ scene: UIScene) {
    guard enabled, let ws = scene as? UIWindowScene else { return }
    for window in ws.windows { cover(window) }
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    guard let ws = scene as? UIWindowScene else { return }
    for window in ws.windows { uncover(window) }
  }

  // Varianta fără scene (rezervă).
  func applicationWillResignActive(_ application: UIApplication) {
    guard enabled else { return }
    for window in application.windows { cover(window) }
  }

  func applicationDidBecomeActive(_ application: UIApplication) {
    for window in application.windows { uncover(window) }
  }

  private func cover(_ window: UIWindow) {
    if window.viewWithTag(PrivacyShield.tag) != nil { return }
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    blur.frame = window.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blur.tag = PrivacyShield.tag
    window.addSubview(blur)
  }

  private func uncover(_ window: UIWindow) {
    window.viewWithTag(PrivacyShield.tag)?.removeFromSuperview()
  }
}

/// Transcrie notițele vocale cu recunoașterea vocală Apple
/// (canalul `notite/speech`). Pe telefon când iOS o permite pentru limbă,
/// altfel prin serviciul Apple.
class SpeechTranscriber: NSObject, FlutterPlugin {
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "notite/speech", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(SpeechTranscriber(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "transcribe",
      let args = call.arguments as? [String: Any],
      let path = args["path"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    let localeId = (args["locale"] as? String) ?? "ro-RO"
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        guard status == .authorized else {
          result(
            FlutterError(
              code: "denied",
              message: "Permite recunoașterea vocală din Setări → Notițe.",
              details: nil))
          return
        }
        self.run(path: path, localeId: localeId, result: result)
      }
    }
  }

  private func run(path: String, localeId: String, result: @escaping FlutterResult) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)),
      recognizer.isAvailable
    else {
      result(
        FlutterError(
          code: "unavailable",
          message: "Recunoașterea vocală în română nu e disponibilă acum.",
          details: nil))
      return
    }
    self.recognizer = recognizer
    let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
    request.shouldReportPartialResults = false
    let onDevice = recognizer.supportsOnDeviceRecognition
    if onDevice { request.requiresOnDeviceRecognition = true }
    var finished = false
    task = recognizer.recognitionTask(with: request) { res, error in
      DispatchQueue.main.async {
        if finished { return }
        if let res = res, res.isFinal {
          finished = true
          result(["text": res.bestTranscription.formattedString, "onDevice": onDevice])
          self.task = nil
        } else if let error = error {
          finished = true
          // Fără vorbire în înregistrare → text gol, nu eroare.
          let nsError = error as NSError
          if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
            result(["text": "", "onDevice": onDevice])
          } else {
            result(
              FlutterError(
                code: "failed", message: "Transcrierea a eșuat: \(error.localizedDescription)",
                details: nil))
          }
          self.task = nil
        }
      }
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

/// Completarea automată iOS (canalul `notite/autofill`): aplicația scrie
/// pentru extensia AutoFill conturile cu parolă, CRIPTATE (AES-GCM) cu o
/// cheie nouă la fiecare actualizare. Cheia stă în Keychain-ul comun,
/// protejată cu Face ID / codul telefonului; iOS primește doar perechile
/// site – utilizator, ca să propună contul potrivit.
class AutofillBridge: NSObject, FlutterPlugin {
  static let group = "group.com.kappado.notite"
  static let keychainGroup = "FUR5C9CYR8.com.kappado.notite.shared"
  static let service = "notite.autofill"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "notite/autofill", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AutofillBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "sync":
      let logins = (call.arguments as? [[String: Any]]) ?? []
      DispatchQueue.global(qos: .utility).async {
        let ok = Self.write(logins)
        Self.updateIdentities(logins)
        DispatchQueue.main.async { result(ok) }
      }
    case "clear":
      Self.clear()
      result(nil)
    case "status":
      ASCredentialIdentityStore.shared.getState { state in
        DispatchQueue.main.async { result(state.isEnabled) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static var fileURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("autofill.vault")
  }

  private static func keyQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "key",
      kSecAttrAccessGroup as String: keychainGroup,
    ]
  }

  /// Cheie nouă la fiecare scriere: aplicația nu trebuie să citească (și
  /// deci să ceară Face ID) cheia veche.
  private static func write(_ logins: [[String: Any]]) -> Bool {
    guard let url = fileURL,
      let json = try? JSONSerialization.data(withJSONObject: logins)
    else { return false }
    let key = SymmetricKey(size: .bits256)
    guard let sealed = try? AES.GCM.seal(json, using: key), let blob = sealed.combined
    else { return false }
    let keyData = key.withUnsafeBytes { Data($0) }

    SecItemDelete(keyQuery() as CFDictionary)
    var add = keyQuery()
    add[kSecValueData as String] = keyData
    if let access = SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil)
    {
      add[kSecAttrAccessControl as String] = access
    } else {
      add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    var status = SecItemAdd(add as CFDictionary, nil)
    if status != errSecSuccess {
      // Telefon fără cod de blocare: fără Face ID posibil, doar „deblocat”.
      add.removeValue(forKey: kSecAttrAccessControl as String)
      add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      status = SecItemAdd(add as CFDictionary, nil)
    }
    guard status == errSecSuccess else { return false }
    do {
      try blob.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      return true
    } catch {
      return false
    }
  }

  private static func updateIdentities(_ logins: [[String: Any]]) {
    let store = ASCredentialIdentityStore.shared
    store.getState { state in
      guard state.isEnabled else { return }
      let ids: [ASPasswordCredentialIdentity] = logins.compactMap { l in
        guard let host = l["host"] as? String, !host.isEmpty,
          let user = l["user"] as? String,
          let id = l["id"] as? String
        else { return nil }
        return ASPasswordCredentialIdentity(
          serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
          user: user, recordIdentifier: id)
      }
      store.replaceCredentialIdentities(with: ids) { _, error in
        if let error { NSLog("Notite AutoFill: \(error)") }
      }
    }
  }

  private static func clear() {
    SecItemDelete(keyQuery() as CFDictionary)
    if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    ASCredentialIdentityStore.shared.removeAllCredentialIdentities(nil)
  }
}

