import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';  // <-- ADD THIS
import 'presentation/app.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  await Firebase.initializeApp();
  await NotificationService.instance.init();

  runApp(
    const ProviderScope(        // <-- ADD THIS
      child: SupplyGoApp(),
    ),
  );
}
