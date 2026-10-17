class Notebook {
  Notebook({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory Notebook.fromMap(Map<dynamic, dynamic> m) => Notebook(
    id: m['id'] as String,
    name: m['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int),
  );
}
