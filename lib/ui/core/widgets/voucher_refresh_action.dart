import 'package:flutter/material.dart';

/// App-bar refresh control for voucher editors that are already synced to Zoho.
///
/// Hidden when [visible] is false (new / local-only / pending-sync drafts).
/// While [isLoading], shows a compact progress indicator and disables the button.
class VoucherRefreshAction extends StatelessWidget {
  final bool visible;
  final bool isLoading;
  final VoidCallback? onPressed;

  const VoucherRefreshAction({
    super.key,
    required this.visible,
    this.isLoading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'Refresh from Zoho',
      icon: const Icon(Icons.refresh),
      onPressed: onPressed,
    );
  }
}
