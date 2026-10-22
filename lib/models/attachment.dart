/// Metadatele unui atașament. Conținutul binar e păstrat separat
/// (cutia `blobs`), ca lista de atașamente să rămână ușoară.
class Attachment {
  Attachment({
    required this.id,
    required this.noteId,
    required this.name,
    required this.mime,
    required this.size,
    required this.createdAt,
    this.ocrText = '',
  });

  final String id;
  final String noteId;
  final String name;
  final String mime;
  final int size;
  final DateTime createdAt;

  /// Text recunoscut (OCR) din imagine — inclus în căutare.
  String ocrText;

  bool get isImage => mime.startsWith('image/');

  Map<String, dynamic> toMap() => {
    'id': id,
    'noteId': noteId,
    'name': name,
    'mime': mime,
    'size': size,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'ocrText': ocrText,
  };

  factory Attachment.fromMap(Map<dynamic, dynamic> m) => Attachment(
    id: m['id'] as String,
    noteId: m['noteId'] as String,
    name: m['name'] as String,
    mime: m['mime'] as String,
    size: m['size'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
    ocrText: (m['ocrText'] as String?) ?? '',
  );

  static String mimeFromName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'txt' => 'text/plain',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };
  }
}
