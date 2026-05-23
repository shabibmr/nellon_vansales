import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'data/services/injection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resilient Firebase Initializer (prevents crashes if credentials are not yet added in development)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // ignore: avoid_print
    print('Firebase Initialization Sandbox Warning: $e');
  }

  // Boot Dependency Injection & Local Caches (Hive)
  await setupDependencyInjection();

  runApp(const VanSalesApp());
}
