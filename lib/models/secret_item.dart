import 'package:flutter/material.dart';

enum SecretType {
  login('Cont', Icons.person_outline),
  card('Card bancar', Icons.credit_card),
  wifi('Wi-Fi', Icons.wifi);

  const SecretType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Câmp adăugat de utilizator (ex. „Întrebare de securitate”, „IBAN”).
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

/// O intrare din secțiunea „Parole”: cont, card bancar sau rețea Wi-Fi.
/// Câmpurile nefolosite de un tip rămân goale.
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
    this.notes = '',
    List<CustomField>? custom,
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
    DateTime? passwordChangedAt,
  }) : custom = custom ?? [],
       passwordChangedAt = passwordChangedAt ?? createdAt;

  final String id;
  final SecretType type;
  String title;

  // Cont (și Wi-Fi: [username] = numele rețelei, [password] = parola).
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

  String notes;
  List<CustomField> custom;
  bool favorite;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Pentru verificarea „parole vechi”.
  DateTime passwordChangedAt;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    return switch (type) {
      SecretType.login => username.isNotEmpty ? username : 'Cont fără nume',
      SecretType.card => 'Card ${last4.isEmpty ? '' : '•••• $last4'}'.trim(),
      SecretType.wifi => username.isNotEmpty ? username : 'Rețea fără nume',
    };
  }

  /// Textul mic de sub titlu în listă.
  String get subtitle => switch (type) {
    SecretType.login => username.isNotEmpty ? username : url,
    SecretType.card => [
      if (last4.isNotEmpty) '•••• $last4',
      if (cardExpiry.isNotEmpty) cardExpiry,
    ].join('  ·  '),
    SecretType.wifi => username,
  };

  String get cardDigits => cardNumber.replaceAll(RegExp(r'\D'), '');
  String get last4 {
    final d = cardDigits;
    return d.length >= 4 ? d.substring(d.length - 4) : '';
  }

  /// Text pentru căutare (fără parole, CVV sau PIN).
  String get searchText => [
    title,
    url,
    username,
    cardHolder,
    last4,
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
    'notes': notes,
    'custom': [for (final f in custom) f.toMap()],
    'favorite': favorite,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'passwordChangedAt': passwordChangedAt.millisecondsSinceEpoch,
  };

  factory SecretItem.fromMap(Map<dynamic, dynamic> m) {
    String s(String k) => (m[k] as String?) ?? '';
    DateTime d(String k) =>
        DateTime.fromMillisecondsSinceEpoch((m[k] as int?) ?? 0);
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
      notes: s('notes'),
      custom: [
        for (final f in (m['custom'] as List?) ?? const [])
          CustomField.fromMap(f as Map),
      ],
      favorite: (m['favorite'] as bool?) ?? false,
      createdAt: d('createdAt'),
      updatedAt: d('updatedAt'),
      passwordChangedAt: m['passwordChangedAt'] == null
          ? null
          : d('passwordChangedAt'),
    );
  }
}
