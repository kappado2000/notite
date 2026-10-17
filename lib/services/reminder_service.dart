import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';

/// Programează notificări locale pentru mementourile notițelor.
/// Pe platformele fără suport, eșuează silențios — mementoul rămâne
/// vizibil în secțiunea „Mementouri”.
class ReminderService {
  ReminderService._();
  static final instance = ReminderService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Apelat când utilizatorul apasă pe o notificare (payload = id notiță).
  void Function(String noteId)? onOpenNote;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  Future<void> init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          windows: WindowsInitializationSettings(
            appName: 'Notițe',
            appUserModelId: 'com.kappado.notite',
            guid: '6f1c3a52-8d0e-4f7b-9c2a-1e5d7b3f9a40',
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final id = r.payload;
          if (id != null) onOpenNote?.call(id);
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('ReminderService.init: $e');
    }
  }

  Future<void> _requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  int _idFor(Note n) => n.id.hashCode & 0x7fffffff;

  /// Aduce notificarea programată în acord cu starea notiței.
  Future<void> sync(Note note) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _idFor(note));
      final at = note.reminderAt;
      if (at == null ||
          note.reminderDone ||
          note.isTrashed ||
          at.isBefore(DateTime.now())) {
        return;
      }
      await _requestPermissions();
      await _plugin.zonedSchedule(
        id: _idFor(note),
        title: 'Memento: ${note.displayTitle}',
        body: note.plainText.trim().split('\n').first,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        payload: note.id,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'mementouri',
            'Mementouri',
            channelDescription: 'Mementouri pentru notițe',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('ReminderService.sync: $e');
    }
  }

  /// La deconectare: mementourile contului nu mai trebuie să apară.
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('ReminderService.cancelAll: $e');
    }
  }

  Future<void> cancel(Note note) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _idFor(note));
    } catch (e) {
      debugPrint('ReminderService.cancel: $e');
    }
  }
}
