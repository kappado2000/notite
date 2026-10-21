import 'dart:convert';

/// O notiță. Conținutul e stocat ca Delta JSON (flutter_quill), iar
/// [plainText] e o copie text simplu folosită la căutare și previzualizare.
///
/// Toate entitățile au [updatedAt] — necesar pentru sincronizarea viitoare
/// cu Firebase (ultima modificare câștigă).
class Note {
  Note({
    required this.id,
    required this.notebookId,
    this.title = '',
    this.contentJson = '',
    this.plainText = '',
    List<String>? tags,
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.trashedAt,
    this.reminderAt,
    this.reminderDone = false,
    this.locked = false,
  }) : tags = tags ?? [];

  final String id;
  String notebookId;
  String title;
  String contentJson;
  String plainText;
  List<String> tags;
  bool pinned;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? trashedAt;
  DateTime? reminderAt;
  bool reminderDone;

  /// Notiță blocată: conținutul se vede doar după Face ID / amprentă sau
  /// parola contului; în liste și căutare apare doar titlul.
  bool locked;

  bool get isTrashed => trashedAt != null;
  bool get hasReminder => reminderAt != null;

  String get displayTitle => title.trim().isEmpty ? 'Fără titlu' : title.trim();

  /// Delta goală validă pentru flutter_quill.
  static String get emptyContent => jsonEncode([
    {'insert': '\n'},
  ]);

  Map<String, dynamic> toMap() => {
    'id': id,
    'notebookId': notebookId,
    'title': title,
    'contentJson': contentJson,
    'plainText': plainText,
    'tags': tags,
    'pinned': pinned,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'trashedAt': trashedAt?.millisecondsSinceEpoch,
    'reminderAt': reminderAt?.millisecondsSinceEpoch,
    'reminderDone': reminderDone,
    'locked': locked,
  };

  factory Note.fromMap(Map<dynamic, dynamic> m) => Note(
    id: m['id'] as String,
    notebookId: m['notebookId'] as String,
    title: (m['title'] as String?) ?? '',
    contentJson: (m['contentJson'] as String?) ?? emptyContent,
    plainText: (m['plainText'] as String?) ?? '',
    tags: ((m['tags'] as List?) ?? const []).cast<String>().toList(),
    pinned: (m['pinned'] as bool?) ?? false,
    createdAt: _date(m['createdAt'])!,
    updatedAt: _date(m['updatedAt'])!,
    trashedAt: _date(m['trashedAt']),
    reminderAt: _date(m['reminderAt']),
    reminderDone: (m['reminderDone'] as bool?) ?? false,
    locked: (m['locked'] as bool?) ?? false,
  );
}

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
