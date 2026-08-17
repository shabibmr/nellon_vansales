import 'package:flutter/material.dart';

import '../../../../ui/core/extensions/l10n_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';

/// OTP-code step of the login form.
class LoginOtpStep extends StatelessWidget {
  final TextEditingController otpController;
  final String phone;
  final AuthState state;
  final int resendSecondsLeft;
  final VoidCallback onSubmit;
  final VoidCallback onResend;
  final VoidCallback onChangeNumber;

  const LoginOtpStep({
    super.key,
    required this.otpController,
    required this.phone,
    required this.state,
    required this.resendSecondsLeft,
    required this.onSubmit,
    required this.onResend,
    required this.onChangeNumber,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canResend = resendSecondsLeft <= 0;
    final isVerifying = state is AuthVerifyingOtp;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.enterCodeTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.otpSentTo(phone),
          style: TextStyle(
            fontSize: 13,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          enabled: !isVerifying,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 8),
          decoration: InputDecoration(
            counterText: '',
            hintText: l10n.otpHint,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: canResend && !isVerifying ? onResend : null,
            child: Text(
              canResend
                  ? l10n.resendCode
                  : l10n.resendInSeconds(resendSecondsLeft),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: isVerifying ? null : onSubmit,
          child: isVerifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(l10n.verifyButton),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: isVerifying ? null : onChangeNumber,
          child: Text(l10n.changeNumber),
        ),
      ],
    );
  }
}
