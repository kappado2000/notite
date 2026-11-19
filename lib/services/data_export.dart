import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import 'file_opener.dart';
import 'full_backup.dart';
import 'note_pdf.dart';

/// Export și restaurare pornite din interfață (partajare / alegere fișier).
class DataExport {
  static String _stamp() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// PDF cu notițele date (fiecare de la pagină nouă); cele blocate apar
  /// doar cu titlul.
  static Future<void> sharePdf(
    BuildContext context,
    NotesStore store,
    List<Note> notes,
    String name,
  ) => _guard(context, () async {
    if (notes.isEmpty) throw StateError('Nu există notițe de exportat');
    final bytes = await notesToPdf(
      notes,
      store,
      title: name,
      includeLocked: false,
    );
    await FileOpener.share('$name.pdf', 'application/pdf', bytes);
  });

  /// Fișierul de backup (JSON), oferit pentru „Salvează în Fișiere”.
  static Future<void> shareBackup(BuildContext context, NotesStore store) =>
      _guard(context, () async {
        final bytes = utf8.encode(jsonEncode(store.exportBackup()));
        await FileOpener.share(
          'Notite-backup-${_stamp()}.json',
          'application/json',
          bytes,
        );
      });

  /// Alege un fișier de backup și îl restaurează.
  static Future<void> restoreBackup(BuildContext context, NotesStore store) =>
      _guard(context, () async {
        // orice fișier: backup-ul complet are extensia .notite (iOS nu o
        // cunoaște), exportul vechi .json
        final files = await FilePicker.pickFiles(type: FileType.any);
        if (files.isEmpty) return;
        final bytes = await files.first.readAsBytes();
        Object? data;
        if (FullBackup.isEncrypted(bytes)) {
          if (!context.mounted) return;
          final password = await _askPassword(context);
          if (password == null) return;
          data = await FullBackup.decrypt(bytes, password);
        } else {
          try {
            data = jsonDecode(utf8.decode(bytes));
          } catch (_) {
            data = null;
          }
        }
        if (data is! Map<String, dynamic>) {
          throw const FormatException('Fișierul nu este un backup Notițe.');
        }
        final r = await store.importBackup(data);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r.notes + r.notebooks + r.attachments + r.secrets == 0
                  ? 'Totul era deja în aplicație — nimic de restaurat'
                  : 'Restaurate: ${r.notes} notițe, ${r.notebooks} carnete, '
                        '${r.attachments} atașamente, ${r.secrets} parole',
            ),
          ),
        );
      });

  static Future<String?> _askPassword(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parola de backup'),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Parola cu care a fost făcut backup-ul',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Deschide'),
          ),
        ],
      ),
    ).whenComplete(c.dispose);
  }

  static Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nu a reușit: $e')));
    }
  }
}
