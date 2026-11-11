class Notebook {
  Notebook({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.emoji = '📒',
    this.color = 0,
    this.intensity = 1,
    this.textMode = 0,
  });

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Emoji afișat lângă nume.
  String emoji;

  /// Indexul în `notebookColors` (theme.dart).
  int color;

  /// Intensitatea nuanței (0…5, `GroupTint.levelNames`); 1 = implicit.
  int intensity;

  /// Culoarea scrisului: indexul în `TintText` (0 = automat).
  int textMode;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'emoji': emoji,
    'color': color,
    'intensity': intensity,
    'textMode': textMode,
  };

  factory Notebook.fromMap(Map<dynamic, dynamic> m) => Notebook(
    id: m['id'] as String,
    name: m['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int),
    emoji: (m['emoji'] as String?) ?? '📒',
    color: (m['color'] as int?) ?? 0,
    intensity: (m['intensity'] as int?) ?? 1,
    textMode: (m['textMode'] as int?) ?? 0,
  );
}
