import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  
  // Global navigator key for handling notification taps
  static GlobalKey<NavigatorState>? navigatorKey;

  static const AndroidNotificationChannel _defaultChannel =
      AndroidNotificationChannel(
        'basood_notifications',
        'Basood Notifications',
        description: 'General alerts and updates from Basood',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_defaultChannel);

    _initialized = true;
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    try {
      if (!_initialized) {
        await init();
      }

      final notification = message.notification;
      final title = notification?.title ?? message.data['title'] ?? 'Basood';
      final body = notification?.body ?? message.data['body'] ?? 'You have a new notification';

      final androidDetails = AndroidNotificationDetails(
        _defaultChannel.id,
        _defaultChannel.name,
        channelDescription: _defaultChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
        playSound: true,
        enableVibration: true,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _plugin.show(
        message.hashCode,
        title,
        body,
        details,
        payload: message.data.isNotEmpty ? message.data.toString() : null,
      );
    } catch (e) {
      debugPrint('❌ Error showing notification: $e');
      // Don't throw - notifications should not crash the app
    }
  }

  void handleNotificationTap(RemoteMessage message) {
    try {
      debugPrint('📱 Notification tapped: ${message.notification?.title}');
      
      // Trigger WebView refresh via a static callback
      // This will refresh the WebView if it's currently displayed
      Future.microtask(() {
        try {
          _onNotificationTapped?.call();
        } catch (e) {
          debugPrint('❌ Error calling notification tap callback: $e');
        }
      });
    } catch (e) {
      debugPrint('❌ Error handling notification tap: $e');
    }
  }
  
  // Callback for WebView refresh when notification is tapped
  static VoidCallback? _onNotificationTapped;
  
  static void setNotificationTapCallback(VoidCallback? callback) {
    _onNotificationTapped = callback;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    try {
      debugPrint('📱 Local notification clicked with payload: ${response.payload}');
      // Refresh WebView or navigate if needed
      // Navigate to WebView screen if not already there
      if (navigatorKey?.currentState != null) {
        // The app will handle navigation
      }
    } catch (e) {
      debugPrint('❌ Error handling notification response: $e');
    }
  }
}
