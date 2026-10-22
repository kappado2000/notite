import 'package:flutter/material.dart';

enum SecretType {
  login('Cont', Icons.person_outline),
  card('Card bancar', Icons.credit_card),
  bank('Cont bancar', Icons.account_balance_outlined),
  identity('Act de identitate', Icons.badge_outlined),
  subscription('Abonament', Icons.autorenew),
  wifi('Wi-Fi', Icons.wifi),
  note('Notă securizată', Icons.sticky_note_2_outlined);

  const SecretType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Felul actului (pentru [SecretType.identity]).
enum DocKind {
  ci('Carte de identitate'),
  passport('Pașaport'),
  license('Permis de conducere'),
  other('Alt act');

  const DocKind(this.label);
  final String label;

  static DocKind parse(String? s) =>
      DocKind.values.firstWhere((k) => k.name == s, orElse: () => DocKind.ci);
}

/// Perioada de plată a unui abonament.
enum BillingPeriod {
  weekly('săptămânal', 52 / 12),
  monthly('lunar', 1),
  quarterly('trimestrial', 1 / 3),
  yearly('anual', 1 / 12);

  const BillingPeriod(this.label, this.perMonth);
  final String label;

  /// De câte ori pe lună (pentru totalul lunar).
  final double perMonth;

  static BillingPeriod parse(String? s) => BillingPeriod.values.firstWhere(
    (p) => p.name == s,
    orElse: () => BillingPeriod.monthly,
  );
}

/// Câmp adăugat de utilizator (ex. „Întrebare de securitate”).
class CustomField {
  CustomField({this.label = '', this.value = '', this.hidden = false});

  String label;
  String value;

  /// Ascuns implicit, ca o parolă.
  bool hidden;

  Map<String, dynamic> toMap() => {
    'label': label,
    'value': value,
    'hidden': hidden,
  };

  factory CustomField.fromMap(Map<dynamic, dynamic> m) => CustomField(
    label: (m['label'] as String?) ?? '',
    value: (m['value'] as String?) ?? '',
    hidden: (m['hidden'] as bool?) ?? false,
  );
}

/// O parolă anterioară (istoric la schimbare).
class PasswordVersion {
  const PasswordVersion(this.password, this.until);
  final String password;

  /// Până când a fost folosită (momentul schimbării).
  final DateTime until;

  Map<String, dynamic> toMap() => {
    'password': password,
    'until': until.millisecondsSinceEpoch,
  };

  factory PasswordVersion.fromMap(Map<dynamic, dynamic> m) => PasswordVersion(
    (m['password'] as String?) ?? '',
    DateTime.fromMillisecondsSinceEpoch((m['until'] as int?) ?? 0),
  );
}

/// O intrare din secțiunea „Parole”. Câmpurile nefolosite de un tip rămân
/// goale.
class SecretItem {
  SecretItem({
    required this.id,
    required this.type,
    this.title = '',
    this.url = '',
    this.username = '',
    this.password = '',
    this.totp = '',
    this.cardHolder = '',
    this.cardNumber = '',
    this.cardExpiry = '',
    this.cardCvv = '',
    this.cardPin = '',
    this.wifiSecurity = 'WPA',
    this.wifiHidden = false,
    this.holder = '',
    this.bankName = '',
    this.iban = '',
    this.swift = '',
    this.docKind = DocKind.ci,
    this.lastName = '',
    this.firstName = '',
    this.address = '',
    this.docSeries = '',
    this.docNumber = '',
    this.cnp = '',
    this.issuedBy = '',
    this.issueDate,
    this.expiryDate,
    this.price = '',
    this.currency = 'RON',
    this.period = BillingPeriod.monthly,
    this.renewalDate,
    this.notes = '',
    List<CustomField>? custom,
    List<PasswordVersion>? passwordHistory,
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
    DateTime? passwordChangedAt,
  }) : custom = custom ?? [],
       passwordHistory = passwordHistory ?? [],
       passwordChangedAt = passwordChangedAt ?? createdAt;

  final String id;
  final SecretType type;
  String title;

  // Cont, abonament (și Wi-Fi: [username] = numele rețelei).
  String url;
  String username;
  String password;

  /// Cheia secretă 2FA (Base32) sau un link `otpauth://`.
  String totp;

  // Card bancar.
  String cardHolder;
  String cardNumber;
  String cardExpiry;
  String cardCvv;
  String cardPin;

  // Wi-Fi: WPA, WEP sau nopass.
  String wifiSecurity;
  bool wifiHidden;

  // Cont bancar și act: titularul.
  String holder;
  String bankName;
  String iban;
  String swift;

  // Act de identitate.
  DocKind docKind;
  String lastName;
  String firstName;
  String address;
  String docSeries;
  String docNumber;
  String cnp;
  String issuedBy;
  DateTime? issueDate;
  DateTime? expiryDate;

  // Abonament.
  String price;
  String currency;
  BillingPeriod period;
  DateTime? renewalDate;

  String notes;
  List<CustomField> custom;

  /// Parolele anterioare, cea mai recentă prima (max. 10).
  List<PasswordVersion> passwordHistory;
  bool favorite;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Pentru verificarea „parole vechi”.
  DateTime passwordChangedAt;

  /// Id-ul folosit pentru atașamentele acestei intrări.
  String get attachmentOwnerId => 'secret:$id';

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    return switch (type) {
      SecretType.login => username.isNotEmpty ? username : 'Cont fără nume',
      SecretType.card => 'Card ${last4.isEmpty ? '' : '•••• $last4'}'.trim(),
      SecretType.bank => bankName.isNotEmpty ? bankName : 'Cont bancar',
      SecretType.identity =>
        fullName.isNotEmpty ? '${docKind.label} · $fullName' : docKind.label,
      SecretType.subscription => 'Abonament',
      SecretType.wifi => username.isNotEmpty ? username : 'Rețea fără nume',
      SecretType.note => 'Notă securizată',
    };
  }

  /// Textul mic de sub titlu în listă (fără date sensibile complete).
  String get subtitle => switch (type) {
    SecretType.login => username.isNotEmpty ? username : url,
    SecretType.card => [
      if (last4.isNotEmpty) '•••• $last4',
      if (cardExpiry.isNotEmpty) cardExpiry,
    ].join('  ·  '),
    SecretType.bank => [
      if (bankName.isNotEmpty && title.trim().isNotEmpty) bankName,
      if (ibanCompact.length >= 4)
        '•••• ${ibanCompact.substring(ibanCompact.length - 4)}',
    ].join('  ·  '),
    SecretType.identity => [
      // Fără titlu propriu, tipul actului e deja în titlu.
      if (title.trim().isNotEmpty) docKind.label,
      if (expiryDate != null) 'expiră ${_d(expiryDate!)}',
    ].join('  ·  '),
    SecretType.subscription => [
      if (price.isNotEmpty) '$price $currency / ${period.label}',
      if (renewalDate != null) 'reînnoire ${_d(renewalDate!)}',
    ].join('  ·  '),
    SecretType.wifi => username,
    SecretType.note => '',
  };

  String get fullName => '$lastName $firstName'.trim();

  String get cardDigits => cardNumber.replaceAll(RegExp(r'\D'), '');
  String get last4 {
    final d = cardDigits;
    return d.length >= 4 ? d.substring(d.length - 4) : '';
  }

  String get ibanCompact => iban.replaceAll(RegExp(r'\s'), '').toUpperCase();

  /// Data de la care intrarea „expiră”: cardul (ultima zi a lunii),
  /// actul, sau reînnoirea abonamentului. Folosită pentru mementouri.
  DateTime? get expiresOn => switch (type) {
    SecretType.card => cardExpiryDate,
    SecretType.identity => expiryDate,
    SecretType.subscription => renewalDate,
    _ => null,
  };

  DateTime? get cardExpiryDate {
    final m = RegExp(r'^(\d{2})\s*/\s*(\d{2,4})$')
        .firstMatch(cardExpiry.trim());
    if (m == null) return null;
    final month = int.parse(m[1]!);
    var year = int.parse(m[2]!);
    if (year < 100) year += 2000;
    if (month < 1 || month > 12) return null;
    return DateTime(year, month + 1, 0); // ultima zi a lunii
  }

  /// Costul lunar (abonamente), pentru total.
  double? get monthlyCost {
    final v = double.tryParse(price.replaceAll(',', '.').trim());
    return v == null ? null : v * period.perMonth;
  }

  /// Text pentru căutare (fără parole, CVV, PIN, CNP).
  String get searchText => [
    title,
    url,
    username,
    cardHolder,
    last4,
    holder,
    bankName,
    docKind.label,
    lastName,
    firstName,
    notes,
    for (final f in custom) f.label,
  ].join(' ');

  SecretItem copy() => SecretItem.fromMap(toMap());

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'title': title,
    'url': url,
    'username': username,
    'password': password,
    'totp': totp,
    'cardHolder': cardHolder,
    'cardNumber': cardNumber,
    'cardExpiry': cardExpiry,
    'cardCvv': cardCvv,
    'cardPin': cardPin,
    'wifiSecurity': wifiSecurity,
    'wifiHidden': wifiHidden,
    'holder': holder,
    'bankName': bankName,
    'iban': iban,
    'swift': swift,
    'docKind': docKind.name,
    'lastName': lastName,
    'firstName': firstName,
    'address': address,
    'docSeries': docSeries,
    'docNumber': docNumber,
    'cnp': cnp,
    'issuedBy': issuedBy,
    'issueDate': issueDate?.millisecondsSinceEpoch,
    'expiryDate': expiryDate?.millisecondsSinceEpoch,
    'price': price,
    'currency': currency,
    'period': period.name,
    'renewalDate': renewalDate?.millisecondsSinceEpoch,
    'notes': notes,
    'custom': [for (final f in custom) f.toMap()],
    'passwordHistory': [for (final p in passwordHistory) p.toMap()],
    'favorite': favorite,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'passwordChangedAt': passwordChangedAt.millisecondsSinceEpoch,
  };

  factory SecretItem.fromMap(Map<dynamic, dynamic> m) {
    String s(String k) => (m[k] as String?) ?? '';
    DateTime d(String k) =>
        DateTime.fromMillisecondsSinceEpoch((m[k] as int?) ?? 0);
    DateTime? od(String k) => m[k] == null ? null : d(k);
    return SecretItem(
      id: m['id'] as String,
      type: SecretType.values.firstWhere(
        (t) => t.name == m['type'],
        orElse: () => SecretType.login,
      ),
      title: s('title'),
      url: s('url'),
      username: s('username'),
      password: s('password'),
      totp: s('totp'),
      cardHolder: s('cardHolder'),
      cardNumber: s('cardNumber'),
      cardExpiry: s('cardExpiry'),
      cardCvv: s('cardCvv'),
      cardPin: s('cardPin'),
      wifiSecurity: (m['wifiSecurity'] as String?) ?? 'WPA',
      wifiHidden: (m['wifiHidden'] as bool?) ?? false,
      holder: s('holder'),
      bankName: s('bankName'),
      iban: s('iban'),
      swift: s('swift'),
      docKind: DocKind.parse(m['docKind'] as String?),
      lastName: s('lastName'),
      firstName: s('firstName'),
      address: s('address'),
      docSeries: s('docSeries'),
      docNumber: s('docNumber'),
      cnp: s('cnp'),
      issuedBy: s('issuedBy'),
      issueDate: od('issueDate'),
      expiryDate: od('expiryDate'),
      price: s('price'),
      currency: (m['currency'] as String?) ?? 'RON',
      period: BillingPeriod.parse(m['period'] as String?),
      renewalDate: od('renewalDate'),
      notes: s('notes'),
      custom: [
        for (final f in (m['custom'] as List?) ?? const [])
          CustomField.fromMap(f as Map),
      ],
      passwordHistory: [
        for (final p in (m['passwordHistory'] as List?) ?? const [])
          PasswordVersion.fromMap(p as Map),
      ],
      favorite: (m['favorite'] as bool?) ?? false,
      createdAt: d('createdAt'),
      updatedAt: d('updatedAt'),
      passwordChangedAt: od('passwordChangedAt'),
    );
  }
}

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
