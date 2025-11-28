import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'theme/app_theme.dart';
import 'features/splash_screen.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../presentation/providers/di_providers.dart';

// Global navigator key for notification handling
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class SupplyGoApp extends ConsumerStatefulWidget {
  const SupplyGoApp({super.key});

  @override
  ConsumerState<SupplyGoApp> createState() => _SupplyGoAppState();
}

class _SupplyGoAppState extends ConsumerState<SupplyGoApp> {
  @override
  void initState() {
    super.initState();
    
    // Configure status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    
    // Set navigator key for notification service
    NotificationService.navigatorKey = navigatorKey;
    
    // Initialize Firebase with Dio after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dio = ref.read(dioProvider);
      FirebaseService.initialize(dio: dio);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Basood',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
