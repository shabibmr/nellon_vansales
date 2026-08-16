// \file main.dart
// \brief Entry point for the Van Sales Pro mobile application.
//
// This file initializes the application binding, boots remote and local dependencies
// (Firebase, dependency injection, and local Hive caches), and runs the root application widget.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'app.dart';
import 'data/services/app_logger.dart';
import 'data/services/injection.dart';
import 'firebase_options.dart';

/// Application entry point.
///
/// Ensures framework bindings are initialized, handles resilient Firebase setup
/// for sandbox environment flexibility, initializes local storage repositories, and mounts
/// the [VanSalesApp] root widget.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resilient Firebase Initializer (prevents crashes if credentials are not yet added in development)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Pass all uncaught Flutter framework errors to Crashlytics
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };

    // Pass all uncaught asynchronous errors to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    AppLogger.warning('Startup', 'Firebase Initialization Sandbox Warning: $e');
  }

  // Boot Dependency Injection & Local Caches (Hive)
  await setupDependencyInjection();

  runApp(const VanSalesApp());
}
