import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await _notificationsPlugin.initialize(initializationSettings);

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    List<dynamic>? actions,
    String? payload,
  }) async {
    final List<AndroidNotificationAction> androidActions = (actions ?? []).map((a) {
      final action = a as Map<String, dynamic>;
      return AndroidNotificationAction(
        action['id'] ?? 'action',
        action['label'] ?? 'Action',
      );
    }).toList();

    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'hub_notifications',
      'Developer Hub',
      channelDescription: 'Notifications mirrored from the desktop agent',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      actions: androidActions.isNotEmpty ? androidActions : null,
    );
    final NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await _notificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }
}
