import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Human-readable label for a Zoho Books transfer-order [status].
String stockTransferStatusLabel(String status) {
  switch (status) {
    case 'draft':
      return 'Draft';
    case 'pending_approval':
      return 'Pending Approval';
    case 'approved':
      return 'Approved';
    case 'in_transit':
      return 'In Transit';
    case 'partially_transferred':
      return 'Partially Transferred';
    case 'transferred':
      return 'Transferred';
    case 'void':
      return 'Void';
    default:
      return status.isEmpty ? 'Draft' : status;
  }
}

/// Badge color for a Zoho Books transfer-order [status]. Draft (still
/// editable) uses [AppTheme.warningAmber]; a terminal/void status uses
/// [AppTheme.errorRose]; everything else (in progress toward completion)
/// uses [AppTheme.successEmerald].
Color stockTransferStatusColor(String status) {
  switch (status) {
    case 'draft':
      return AppTheme.warningAmber;
    case 'void':
      return AppTheme.errorRose;
    default:
      return AppTheme.successEmerald;
  }
}
