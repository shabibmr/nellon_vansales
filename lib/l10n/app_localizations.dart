import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application title string
  ///
  /// In en, this message translates to:
  /// **'Nellon Van Sales'**
  String get appTitle;

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboardTitle;

  /// No description provided for @operationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get operationsTitle;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @customersAndRoutes.
  ///
  /// In en, this message translates to:
  /// **'Customers & Routes'**
  String get customersAndRoutes;

  /// No description provided for @analyticsDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics & Dashboard'**
  String get analyticsDashboardTitle;

  /// No description provided for @operationsPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Operations Panel'**
  String get operationsPanelTitle;

  /// No description provided for @reportsStatementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports & Statements'**
  String get reportsStatementsTitle;

  /// No description provided for @loginWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Van Sales'**
  String get loginWelcome;

  /// No description provided for @enterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter phone number to receive OTP'**
  String get enterPhoneNumber;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumberLabel;

  /// No description provided for @sendOtpButton.
  ///
  /// In en, this message translates to:
  /// **'SEND VERIFICATION CODE'**
  String get sendOtpButton;

  /// No description provided for @verifyOtpButton.
  ///
  /// In en, this message translates to:
  /// **'VERIFY & LOGIN'**
  String get verifyOtpButton;

  /// No description provided for @brandName.
  ///
  /// In en, this message translates to:
  /// **'VAN SALES PRO'**
  String get brandName;

  /// No description provided for @brandSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Predefined Routes & Zoho Books Integration'**
  String get brandSubtitle;

  /// No description provided for @agentSignIn.
  ///
  /// In en, this message translates to:
  /// **'Agent Sign In'**
  String get agentSignIn;

  /// No description provided for @loginPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your registered mobile number to receive a login code.'**
  String get loginPhoneHint;

  /// No description provided for @mobileNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get mobileNumberLabel;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'+<country code><number>'**
  String get phoneHint;

  /// No description provided for @invalidPhoneFormat.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid mobile number in international format (e.g. +971501234567)'**
  String get invalidPhoneFormat;

  /// No description provided for @sendCodeButton.
  ///
  /// In en, this message translates to:
  /// **'SEND CODE'**
  String get sendCodeButton;

  /// No description provided for @enterCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Code'**
  String get enterCodeTitle;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'A 6-digit code was sent to {phone}.'**
  String otpSentTo(String phone);

  /// No description provided for @otpHint.
  ///
  /// In en, this message translates to:
  /// **'••••••'**
  String get otpHint;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// No description provided for @resendInSeconds.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String resendInSeconds(int seconds);

  /// No description provided for @verifyButton.
  ///
  /// In en, this message translates to:
  /// **'VERIFY'**
  String get verifyButton;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get changeNumber;

  /// No description provided for @syncStatusSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncStatusSynced;

  /// No description provided for @syncStatusSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncStatusSyncing;

  /// No description provided for @syncStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get syncStatusPending;

  /// No description provided for @offlineBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing cached data'**
  String get offlineBannerMessage;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrong;

  /// No description provided for @loadingActiveRoute.
  ///
  /// In en, this message translates to:
  /// **'Loading active route…'**
  String get loadingActiveRoute;

  /// No description provided for @verifyingSession.
  ///
  /// In en, this message translates to:
  /// **'Verifying session…'**
  String get verifyingSession;

  /// No description provided for @salesInvoicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales Invoices'**
  String get salesInvoicesTitle;

  /// No description provided for @salesInvoicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View, filter, edit, or create offline sales invoices.'**
  String get salesInvoicesSubtitle;

  /// No description provided for @newSalesInvoice.
  ///
  /// In en, this message translates to:
  /// **'New Sales Invoice'**
  String get newSalesInvoice;

  /// No description provided for @salesOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales Orders'**
  String get salesOrdersTitle;

  /// No description provided for @salesOrdersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View, filter, edit, or create offline sales orders.'**
  String get salesOrdersSubtitle;

  /// No description provided for @newSalesOrder.
  ///
  /// In en, this message translates to:
  /// **'New Sales Order'**
  String get newSalesOrder;

  /// No description provided for @salesReturnsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales Returns'**
  String get salesReturnsTitle;

  /// No description provided for @salesReturnsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View, filter, edit, or create credit notes for returned goods.'**
  String get salesReturnsSubtitle;

  /// No description provided for @newSalesReturn.
  ///
  /// In en, this message translates to:
  /// **'New Sales Return'**
  String get newSalesReturn;

  /// No description provided for @expensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesTitle;

  /// No description provided for @expensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and log van trip expenses with receipt capture.'**
  String get expensesSubtitle;

  /// No description provided for @newExpense.
  ///
  /// In en, this message translates to:
  /// **'New Expense'**
  String get newExpense;

  /// No description provided for @receiptsTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get receiptsTitle;

  /// No description provided for @receiptsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and log customer payment receipt vouchers.'**
  String get receiptsSubtitle;

  /// No description provided for @newReceipt.
  ///
  /// In en, this message translates to:
  /// **'New Receipt'**
  String get newReceipt;

  /// No description provided for @issueToVanTitle.
  ///
  /// In en, this message translates to:
  /// **'Issue to Van'**
  String get issueToVanTitle;

  /// No description provided for @issueToVanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and plan stock loaded from the default warehouse onto the van.'**
  String get issueToVanSubtitle;

  /// No description provided for @newIssueToVan.
  ///
  /// In en, this message translates to:
  /// **'New Issue to Van'**
  String get newIssueToVan;

  /// No description provided for @stockUnloadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock Unloading'**
  String get stockUnloadingTitle;

  /// No description provided for @stockUnloadingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and return the van\'s balance stock back to the default warehouse.'**
  String get stockUnloadingSubtitle;

  /// No description provided for @newStockUnloading.
  ///
  /// In en, this message translates to:
  /// **'New Stock Unloading'**
  String get newStockUnloading;

  /// No description provided for @dailyCashClosingTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Cash Closing'**
  String get dailyCashClosingTitle;

  /// No description provided for @dailyCashClosingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'End of session cash count, inventory check & Zoho reconciliation.'**
  String get dailyCashClosingSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
