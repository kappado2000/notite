import AuthenticationServices
import CryptoKit
import LocalAuthentication
import UIKit

/// Extensia „Completare automată” a Notițe: furnizează parolele salvate în
/// Notițe în orice aplicație și în Safari.
///
/// Siguranță: aplicația Notițe scrie în grupul comun doar fișierul criptat
/// (AES-GCM) cu conturile; cheia stă în Keychain, protejată cu Face ID /
/// codul telefonului. Fără deblocare, extensia nu vede nici măcar lista.
final class CredentialProviderViewController: ASCredentialProviderViewController,
  UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate
{
  private struct Login: Decodable {
    let id: String
    let title: String
    let url: String
    let host: String
    let user: String
    let password: String
  }

  private var logins: [Login] = []
  private var shown: [Login] = []
  private var matching = Set<String>()
  private var serviceHosts: [String] = []

  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private let search = UISearchBar()
  private let message = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    AutofillLog.write("extensie: pornită")
  }

  /// Face ID se poate cere doar după ce fereastra extensiei e pe ecran
  /// (altfel iOS refuză: eroarea -25308). Cererile așteaptă până atunci.
  private var appeared = false
  private var waiting: [() -> Void] = []

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    appeared = true
    let run = waiting
    waiting.removeAll()
    run.forEach { $0() }
  }

  private func whenVisible(_ action: @escaping () -> Void) {
    if appeared { action() } else { waiting.append(action) }
  }

  // MARK: - Lista de conturi (din bara de deasupra tastaturii → „Parole”)

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    AutofillLog.write(
      "extensie: listă pentru \(serviceIdentifiers.map(\.identifier).joined(separator: ", "))")
    serviceHosts = serviceIdentifiers.map { Self.host(of: $0.identifier) }.filter { !$0.isEmpty }
    buildUI()
    unlock { [weak self] ok in
      guard let self else { return }
      if ok { self.filter("") } else { self.showMessage(Self.lockedText) }
    }
  }

  // MARK: - Contul propus direct de iOS

  override func provideCredentialWithoutUserInteraction(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    AutofillLog.write("extensie: cerere directă (veche) → cer Face ID")
    // Fără Face ID nu dăm nicio parolă.
    extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
  }

  // iOS 17+: aceleași cereri, prin funcțiile noi.
  @available(iOS 17.0, *)
  override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
    AutofillLog.write("extensie: cerere directă (nouă) → cer Face ID")
    extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
  }

  @available(iOS 17.0, *)
  override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
    AutofillLog.write("extensie: cerere cu interfață (nouă)")
    guard let identity = credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity
    else {
      AutofillLog.write("extensie: cerere care nu e de parolă — anulată")
      extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
      return
    }
    showCredential(identity)
  }

  override func prepareInterfaceToProvideCredential(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    AutofillLog.write("extensie: cerere cu interfață (veche)")
    showCredential(credentialIdentity)
  }

  private func showCredential(_ credentialIdentity: ASPasswordCredentialIdentity) {
    buildUI()
    showMessage("Se deschide seiful…")
    unlock { [weak self] ok in
      guard let self else { return }
      guard ok,
        let login = self.logins.first(where: { $0.id == credentialIdentity.recordIdentifier })
      else {
        AutofillLog.write(ok ? "extensie: contul nu e în listă" : "extensie: seiful nu s-a deschis")
        self.showMessage(ok ? "Contul nu mai există în Notițe." : Self.lockedText)
        return
      }
      AutofillLog.write("extensie: parolă dată")
      self.complete(login)
    }
  }

  // MARK: - Activarea din Setări

  override func prepareInterfaceForExtensionConfiguration() {
    buildUI()
    search.isHidden = true
    showMessage(
      "Notițe completează acum parolele.\n\nDeschide o dată aplicația Notițe, "
        + "ca lista conturilor să ajungă la iOS.")
    navigationItemDone {
      self.extensionContext.completeExtensionConfigurationRequest()
    }
  }

  // MARK: - Deblocare și citire

  private static let lockedText =
    "Seiful nu s-a deschis.\n\nDeschide o dată aplicația Notițe și încearcă din nou."

  /// Citește cheia din Keychain (iOS cere Face ID / codul) și decriptează.
  /// Întâi Face ID / codul (fereastra sistemului), apoi cheia din Keychain
  /// citită cu aceeași confirmare — fără a doua cerere.
  private func unlock(_ done: @escaping (Bool) -> Void) {
    whenVisible {
      let context = LAContext()
      context.localizedFallbackTitle = "Folosește codul"
      context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: "Deblochează parolele din Notițe"
      ) { ok, error in
        guard ok else {
          AutofillLog.write(
            "extensie: Face ID refuzat/anulat — \((error as NSError?)?.code ?? 0)")
          DispatchQueue.main.async { done(false) }
          return
        }
        AutofillLog.write("extensie: Face ID ok")
        let list = AutofillVault.read(context: context)
        DispatchQueue.main.async {
          if let list {
            // dubluri (același site + utilizator): rămâne cel mai nou
            var seen = Set<String>()
            self.logins = list.compactMap {
              try? JSONDecoder().decode(
                Login.self, from: JSONSerialization.data(withJSONObject: $0))
            }.filter { seen.insert($0.host.lowercased() + "|" + $0.user.lowercased()).inserted }
            done(true)
          } else {
            done(false)
          }
        }
      }
    }
  }

  private func complete(_ login: Login) {
    extensionContext.completeRequest(
      withSelectedCredential: ASPasswordCredential(user: login.user, password: login.password),
      completionHandler: nil)
  }

  // MARK: - Interfață

  private func buildUI() {
    guard table.superview == nil else { return }
    view.backgroundColor = .systemGroupedBackground

    let bar = UINavigationBar()
    bar.translatesAutoresizingMaskIntoConstraints = false
    let item = UINavigationItem(title: "Notițe – Parole")
    item.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    bar.items = [item]
    view.addSubview(bar)

    search.translatesAutoresizingMaskIntoConstraints = false
    search.placeholder = "Caută cont, site, utilizator"
    search.searchBarStyle = .minimal
    search.delegate = self
    view.addSubview(search)

    table.translatesAutoresizingMaskIntoConstraints = false
    table.dataSource = self
    table.delegate = self
    table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    view.addSubview(table)

    message.translatesAutoresizingMaskIntoConstraints = false
    message.numberOfLines = 0
    message.textAlignment = .center
    message.textColor = .secondaryLabel
    message.isHidden = true
    view.addSubview(message)

    NSLayoutConstraint.activate([
      bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      search.topAnchor.constraint(equalTo: bar.bottomAnchor),
      search.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      search.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
      table.topAnchor.constraint(equalTo: search.bottomAnchor),
      table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
      message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
    ])
  }

  private func navigationItemDone(_ action: @escaping () -> Void) {
    doneAction = action
    if let bar = view.subviews.compactMap({ $0 as? UINavigationBar }).first {
      bar.items?.first?.leftBarButtonItem = nil
      bar.items?.first?.rightBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .done, target: self, action: #selector(done))
    }
  }

  private var doneAction: (() -> Void)?
  @objc private func done() { doneAction?() }

  @objc private func cancel() {
    extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
  }

  private func showMessage(_ text: String) {
    message.text = text
    message.isHidden = false
    table.isHidden = true
  }

  private func filter(_ query: String) {
    message.isHidden = true
    table.isHidden = false
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    // Aplicațiile fără domeniu web (ex. iHidro) nu spun ce cont caută:
    // atunci arătăm conturile folosite recent în completarea automată.
    let recent = serviceHosts.isEmpty ? Self.recentIds : []
    matching =
      serviceHosts.isEmpty
      ? Set(recent).intersection(logins.map(\.id))
      : Set(logins.filter(isMatch).map(\.id))
    // Fără căutare: DOAR conturile site-ului (ca „Parole” din iOS), cu
    // „Arată toate conturile” dedesubt. Cu căutare: în toată lista.
    let onlySite = q.isEmpty && !matching.isEmpty && !showAll
    shown =
      logins
      .filter {
        onlySite
          ? matching.contains($0.id)
          : q.isEmpty
            || "\($0.title) \($0.user) \($0.host)".lowercased().contains(q)
      }
      .sorted {
        let a = matching.contains($0.id), b = matching.contains($1.id)
        if a != b { return a }
        if a, let i = recent.firstIndex(of: $0.id), let j = recent.firstIndex(of: $1.id) {
          return i < j
        }
        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
      }
    table.reloadData()
    if logins.isEmpty {
      showMessage("Nicio parolă încă.\n\nDeschide aplicația Notițe o dată, ca să se încarce.")
    }
  }

  private var showAll = false

  /// Contul e pentru site-ul cerut: același domeniu sau, la conturile fără
  /// adresă, numele site-ului în titlu („Hidroelectrica” ↔ hidroelectrica.ro).
  private func isMatch(_ l: Login) -> Bool {
    if serviceHosts.contains(where: { Self.sameSite($0, l.host) }) { return true }
    guard l.host.isEmpty else { return false }
    let title = l.title.lowercased().filter { $0.isLetter || $0.isNumber }
    return serviceHosts.contains { h in
      let label = Self.base(h).split(separator: ".").first.map(String.init) ?? ""
      return label.count >= 4 && title.contains(label)
    }
  }

  /// Rândul „Arată toate conturile” (doar când lista arată conturile site-ului).
  private var hasMoreRow: Bool {
    !showAll && (search.text ?? "").isEmpty && !matching.isEmpty
      && matching.count < logins.count
  }

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    filter(searchText)
  }

  func numberOfSections(in tableView: UITableView) -> Int {
    hasMoreRow ? 2 : 1
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == 0 ? shown.count : 1
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    guard section == 0 && hasMoreRow else { return nil }
    return serviceHosts.isEmpty
      ? "Folosite recent (aplicația nu spune ce cont caută)"
      : "Conturi pentru acest site"
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.section == 1 {
      let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
      cell.textLabel?.text = "Arată toate conturile (\(logins.count))"
      cell.textLabel?.textColor = .systemBlue
      cell.imageView?.image = UIImage(systemName: "list.bullet")
      return cell
    }
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    let l = shown[indexPath.row]
    cell.textLabel?.text = l.title.isEmpty ? l.host : l.title
    cell.detailTextLabel?.text = l.user
    cell.detailTextLabel?.textColor = .secondaryLabel
    cell.imageView?.image = UIImage(
      systemName: matching.contains(l.id) ? "key.fill" : "key")
    cell.imageView?.tintColor = matching.contains(l.id) ? .systemGreen : .secondaryLabel
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    if indexPath.section == 1 {
      showAll = true
      filter(search.text ?? "")
      return
    }
    Self.rememberRecent(shown[indexPath.row].id)
    complete(shown[indexPath.row])
  }

  // MARK: - Folosite recent (doar identificatori, în grupul aplicației)

  private static let recentKey = "autofill.recent"

  static var recentIds: [String] {
    UserDefaults(suiteName: AutofillVault.group)?.stringArray(forKey: recentKey) ?? []
  }

  static func rememberRecent(_ id: String) {
    let d = UserDefaults(suiteName: AutofillVault.group)
    let list = [id] + recentIds.filter { $0 != id }
    d?.set(Array(list.prefix(10)), forKey: recentKey)
  }

  // MARK: - Site-uri

  static func host(of identifier: String) -> String {
    var s = identifier.lowercased()
    if !s.contains("://") { s = "https://" + s }
    var h = URL(string: s)?.host ?? ""
    if h.hasPrefix("www.") { h.removeFirst(4) }
    return h
  }

  private static let twoPart: Set<String> = [
    "co.uk", "com.ro", "org.ro", "info.ro", "com.au", "co.nz", "com.br", "com.tr",
  ]

  static func base(_ host: String) -> String {
    let p = host.split(separator: ".").map(String.init)
    guard p.count > 2 else { return host }
    let last2 = p.suffix(2).joined(separator: ".")
    return twoPart.contains(last2) ? p.suffix(3).joined(separator: ".") : last2
  }

  static func sameSite(_ a: String, _ b: String) -> Bool {
    !a.isEmpty && !b.isEmpty && base(a) == base(b)
  }
}

/// Fișierul criptat comun (grupul de aplicații) + cheia din Keychain.
/// Aceeași logică există și în aplicație (AppDelegate.swift).
enum AutofillVault {
  static let group = "group.com.kappado.notite"
  static let keychainGroup = "FUR5C9CYR8.com.kappado.notite.shared"
  static let service = "notite.autofill"
  static let fileName = "autofill.vault"

  static var fileURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent(fileName)
  }

  /// Cheia (cere Face ID / codul), apoi decriptarea listei de conturi.
  static func read(context: LAContext) -> [[String: Any]]? {
    // contextul e deja confirmat cu Face ID: Keychain-ul nu mai întreabă
    context.interactionNotAllowed = false
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "key",
      kSecAttrAccessGroup as String: keychainGroup,
      kSecReturnData as String: true,
      kSecUseAuthenticationContext as String: context,
    ]
    var out: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    guard status == errSecSuccess, let keyData = out as? Data else {
      AutofillLog.write("extensie: cheia din Keychain — eroare \(status)")
      return nil
    }
    guard let url = fileURL, let blob = try? Data(contentsOf: url) else {
      AutofillLog.write("extensie: fișierul cu conturi lipsește")
      return nil
    }
    guard let box = try? AES.GCM.SealedBox(combined: blob),
      let clear = try? AES.GCM.open(box, using: SymmetricKey(data: keyData)),
      let list = try? JSONSerialization.jsonObject(with: clear) as? [[String: Any]]
    else {
      AutofillLog.write("extensie: decriptarea a eșuat")
      return nil
    }
    AutofillLog.write("extensie: seif deschis, \(list.count) conturi")
    return list
  }
}

/// Jurnal de diagnostic comun (aplicație + extensie), în grupul de aplicații:
/// fiecare pas al completării automate, fără date secrete. Max. ~300 rânduri.
enum AutofillLog {
  static func write(_ text: String) {
    guard
      let url = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.kappado.notite")?
        .appendingPathComponent("autofill.log")
    else { return }
    let f = DateFormatter()
    f.dateFormat = "dd.MM HH:mm:ss"
    let line = "\(f.string(from: Date())) \(text)\n"
    var lines = (try? String(contentsOf: url, encoding: .utf8))?
      .split(separator: "\n", omittingEmptySubsequences: true).map(String.init) ?? []
    lines.append(line.trimmingCharacters(in: .newlines))
    if lines.count > 300 { lines.removeFirst(lines.count - 300) }
    try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
  }
}
