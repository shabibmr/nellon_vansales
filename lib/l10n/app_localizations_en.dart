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
  String get operationsTitle => 'Transactions';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get customersAndRoutes => 'Customers & Routes';

  @override
  String get analyticsDashboardTitle => 'Analytics & Dashboard';

  @override
  String get operationsPanelTitle => 'Transactions Panel';

  @override
  String get reportsStatementsTitle => 'Reports & Statements';

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
  String get brandName => 'VAN SALES PRO';

  @override
  String get brandSubtitle => 'Predefined Routes & Zoho Books Integration';

  @override
  String get agentSignIn => 'Agent Sign In';

  @override
  String get loginPhoneHint =>
      'Enter your registered mobile number to receive a login code.';

  @override
  String get mobileNumberLabel => 'Mobile Number';

  @override
  String get phoneHint => '+<country code><number>';

  @override
  String get invalidPhoneFormat =>
      'Enter a valid mobile number in international format (e.g. +971501234567)';

  @override
  String get sendCodeButton => 'SEND CODE';

  @override
  String get enterCodeTitle => 'Enter Code';

  @override
  String otpSentTo(String phone) {
    return 'A 6-digit code was sent to $phone.';
  }

  @override
  String get otpHint => '••••••';

  @override
  String get resendCode => 'Resend code';

  @override
  String resendInSeconds(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get verifyButton => 'VERIFY';

  @override
  String get changeNumber => 'Change number';

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

  @override
  String get loadingActiveRoute => 'Loading active route…';

  @override
  String get verifyingSession => 'Verifying session…';

  @override
  String get salesInvoicesTitle => 'Sales Invoices';

  @override
  String get salesInvoicesSubtitle =>
      'View, filter, edit, or create offline sales invoices.';

  @override
  String get newSalesInvoice => 'New Sales Invoice';

  @override
  String get salesOrdersTitle => 'Sales Orders';

  @override
  String get salesOrdersSubtitle =>
      'View, filter, edit, or create offline sales orders.';

  @override
  String get newSalesOrder => 'New Sales Order';

  @override
  String get salesReturnsTitle => 'Sales Returns';

  @override
  String get salesReturnsSubtitle =>
      'View, filter, edit, or create credit notes for returned goods.';

  @override
  String get newSalesReturn => 'New Sales Return';

  @override
  String get expensesTitle => 'Expenses';

  @override
  String get expensesSubtitle =>
      'View and log van trip expenses with receipt capture.';

  @override
  String get newExpense => 'New Expense';

  @override
  String get receiptsTitle => 'Receipts';

  @override
  String get receiptsSubtitle =>
      'View and log customer payment receipt vouchers.';

  @override
  String get newReceipt => 'New Receipt';

  @override
  String get issueToVanTitle => 'Issue to Van';

  @override
  String get issueToVanSubtitle =>
      'View and plan stock loaded from the default warehouse onto the van.';

  @override
  String get newIssueToVan => 'New Issue to Van';

  @override
  String get stockUnloadingTitle => 'Stock Unloading';

  @override
  String get stockUnloadingSubtitle =>
      'View and return the van\'s balance stock back to the default warehouse.';

  @override
  String get newStockUnloading => 'New Stock Unloading';

  @override
  String get dailyCashClosingTitle => 'Daily Cash Closing';

  @override
  String get dailyCashClosingSubtitle =>
      'End of session cash count, inventory check & Zoho reconciliation.';
}
