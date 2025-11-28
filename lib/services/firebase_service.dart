import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import '../core/config/api_endpoints.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await NotificationService.instance.init();
    await NotificationService.instance.showRemoteMessage(message);
    print('✅ Background notification handled: ${message.notification?.title}');
  } catch (e) {
    print('❌ Error in background notification handler: $e');
    // Don't rethrow - background handler errors should not crash the app
  }
}

class FirebaseService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static Dio? _dio; // Store Dio instance

  // Call this method to set Dio instance (from Riverpod)
  static void setDio(Dio dio) {
    _dio = dio;
  }

  // Method to send FCM token to backend
  static Future<void> sendTokenToBackend(String token) async {
    if (_dio == null) {
      print('⚠️ Dio not initialized. Cannot send FCM token to backend.');
      return;
    }

    try {
      await _dio!.post(
        BasoodEndpoints.user.registerFcmToken,
        data: {'fcmToken': token},
      );
      print('✅ FCM Token sent to backend successfully');
    } catch (e) {
      print('❌ Failed to send FCM token to backend: $e');
      // Don't throw - notifications should still work even if backend call fails
    }
  }

  static Future<void> initialize({Dio? dio}) async {
    try {
      if (dio != null) {
        setDio(dio);
      }

      await NotificationService.instance.init();

      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print('❌ Notification permission denied');
      } else {
        print('✅ Notification permission status: ${settings.authorizationStatus}');
      }

      // Get initial token and send to backend
      try {
        final token = await _fcm.getToken();
        if (token != null) {
          print('🔑 FCM Token: $token');
          await sendTokenToBackend(token);
        }
      } catch (e) {
        print('⚠️ Error getting FCM token: $e');
        // Don't throw - app should work even if token retrieval fails
      }

      // Listen for token refresh
      _fcm.onTokenRefresh.listen((newToken) async {
        try {
          print('🔄 FCM Token refreshed: $newToken');
          await sendTokenToBackend(newToken);
        } catch (e) {
          print('⚠️ Error sending refreshed token: $e');
          // Don't throw - token refresh should not crash the app
        }
      });
    } catch (e) {
      print('❌ Error initializing Firebase service: $e');
      // Don't throw - app should work even if Firebase initialization fails
    }

    // Handle foreground notifications (app is open)
    FirebaseMessaging.onMessage.listen((message) async {
      print('📩 Foreground notification received: ${message.notification?.title}');
      try {
        await NotificationService.instance.showRemoteMessage(message);
      } catch (e) {
        print('❌ Error showing foreground notification: $e');
      }
    });

    // Handle notifications when app is opened from background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print(
        '📩 Notification opened (from background): ${message.notification?.title}',
      );
      // Trigger app refresh/navigation if needed
      NotificationService.instance.handleNotificationTap(message);
    });

    // Handle notifications when app is opened from terminated state
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      print(
        '📩 Notification opened (from terminated): ${initialMessage.notification?.title}',
      );
      // Trigger app refresh/navigation if needed
      NotificationService.instance.handleNotificationTap(initialMessage);
    }
  }
}
