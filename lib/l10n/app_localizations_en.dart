// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Nellon Van Sales';

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get operationsTitle => 'Operations';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get customersAndRoutes => 'Customers & Routes';

  @override
  String get loginWelcome => 'Welcome to Van Sales';

  @override
  String get enterPhoneNumber => 'Enter phone number to receive OTP';

  @override
  String get phoneNumberLabel => 'Phone Number';

  @override
  String get sendOtpButton => 'SEND VERIFICATION CODE';

  @override
  String get verifyOtpButton => 'VERIFY & LOGIN';

  @override
  String get syncStatusSynced => 'Synced';

  @override
  String get syncStatusSyncing => 'Syncing';

  @override
  String get syncStatusPending => 'Pending';

  @override
  String get offlineBannerMessage => 'Offline — showing cached data';

  @override
  String get somethingWentWrong => 'Something went wrong. Please try again.';
}
