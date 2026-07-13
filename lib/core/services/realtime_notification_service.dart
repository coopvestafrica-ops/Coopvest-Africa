import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'dart:convert';
import '../utils/utils.dart';

/// RealtimeNotificationService
///
/// Subscribes to the Supabase `notifications` table for the current user.
/// When a new row is inserted (e.g. by the admin backend on deposit verify/reject),
/// it shows a local pop-up AND calls [onNewNotification] so the
/// NotificationsProvider can update its in-app list + badge count instantly.
class RealtimeNotificationService {
  static final RealtimeNotificationService _instance =
      RealtimeNotificationService._();
  factory RealtimeNotificationService() => _instance;
  RealtimeNotificationService._();

  sb.RealtimeChannel? _channel;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _localInit = false;

  Function(Map<String, dynamic>)? onNewNotification;

  // ── Init ─────────────────────────────────────────────────────────────────────

  Future<void> _ensureLocalInit() async {
    if (_localInit) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _localInit = true;
  }

  /// Start listening for notifications for [userId].
  /// Call this after the user is authenticated.
  Future<void> subscribe(String userId) async {
    await unsubscribe(); // clean up any previous subscription
    await _ensureLocalInit();

    final client = sb.Supabase.instance.client;

    _channel = client
        .channel('user-notifications-$userId')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: sb.PostgresChangeFilter(
            type: sb.PostgresChangeFilterType.eq,
            column: 'profile_id',
            value: userId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            _handleNewRow(row);
          },
        )
        .subscribe((status, [err]) {
          if (err != null) {
            logger.w('RealtimeNotificationService subscription error: $err');
          } else {
            logger.i('RealtimeNotificationService subscribed for user $userId (status: $status)');
          }
        });
  }

  /// Stop listening. Call on logout.
  Future<void> unsubscribe() async {
    if (_channel != null) {
      await sb.Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
      logger.i('RealtimeNotificationService unsubscribed');
    }
  }

  // ── Row handler ───────────────────────────────────────────────────────────────

  void _handleNewRow(Map<String, dynamic> row) {
    final title = (row['title'] as String?) ?? 'Coopvest Africa';
    final body = (row['body'] as String?) ?? '';
    final type = (row['type'] as String?) ?? 'general';

    logger.i('Realtime notification received: $title ($type)');

    // 1. Show a local pop-up immediately
    _showLocalNotification(title: title, body: body, type: type, payload: jsonEncode(row));

    // 2. Inform the provider so it can prepend to the list + update badge
    onNewNotification?.call(row);
  }

  // ── Local notification display ────────────────────────────────────────────────

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String type,
    required String payload,
  }) async {
    try {
      const channelId = 'wallet_notifications';
      const channelName = 'Wallet Notifications';

      const androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: payload,
      );
    } catch (e) {
      logger.e('RealtimeNotificationService._showLocalNotification error: $e');
    }
  }
}
