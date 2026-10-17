class Notebook {
  Notebook({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.emoji = '📒',
    this.color = 0,
  });

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Emoji afișat lângă nume.
  String emoji;

  /// Indexul în `notebookColors` (theme.dart).
  int color;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'emoji': emoji,
    'color': color,
  };

  factory Notebook.fromMap(Map<dynamic, dynamic> m) => Notebook(
    id: m['id'] as String,
    name: m['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int),
    emoji: (m['emoji'] as String?) ?? '📒',
    color: (m['color'] as int?) ?? 0,
  );
}
