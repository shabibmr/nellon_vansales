// \file main.dart
// \brief Entry point for the Van Sales Pro mobile application.
//
// This file initializes the application binding, boots remote and local dependencies
// (Firebase, dependency injection, and local Hive caches), and runs the root application widget.

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'app.dart';
import 'data/services/app_logger.dart';
import 'data/services/debug_file_logger.dart';
import 'data/services/injection.dart';
import 'firebase_options.dart';
import 'ui/core/bloc/app_bloc_observer.dart';

/// Application entry point.
///
/// Ensures framework bindings are initialized, handles resilient Firebase setup
/// for sandbox environment flexibility, initializes local storage repositories, and mounts
/// the [VanSalesApp] root widget.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DebugFileLogger.log('[Startup] main() begin.');
  Bloc.observer = AppBlocObserver();
  ErrorWidget.builder = (details) {
    return const Material(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Something went wrong. Please try again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  };

  // Resilient Firebase Initializer (prevents crashes if credentials are not yet added in development)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    DebugFileLogger.log('[Startup] Firebase initialized.');

    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

    // Carries over any log lines left from the previous app run so they
    // aren't stranded waiting for the in-session size threshold.
    unawaited(DebugFileLogger.flushPreviousSessionIfAny());

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
    DebugFileLogger.log('[Startup] Firebase initialization failed: $e');
  }

  // Boot Dependency Injection & Local Caches (Hive)
  await setupDependencyInjection();
  DebugFileLogger.log('[Startup] Dependency injection complete.');

  runApp(const VanSalesApp());
  DebugFileLogger.log('[Startup] runApp() called.');
}
