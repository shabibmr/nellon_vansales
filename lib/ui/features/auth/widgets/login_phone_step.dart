import 'package:flutter/material.dart';

import '../../../../domain/utils/phone_normalizer.dart';
import '../../../../ui/core/extensions/l10n_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';

/// Phone-number step of the OTP login form.
class LoginPhoneStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneController;
  final AuthState state;
  final VoidCallback onSubmit;

  const LoginPhoneStep({
    super.key,
    required this.formKey,
    required this.phoneController,
    required this.state,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLoading = state is AuthLoading;
    final l10n = context.l10n;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.agentSignIn,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.loginPhoneHint,
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(
              labelText: l10n.mobileNumberLabel,
              hintText: l10n.phoneHint,
            ),
            validator: (value) {
              final normalized = normalizePhone((value ?? '').trim());
              if (!isValidE164(normalized)) {
                return l10n.invalidPhoneFormat;
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: isLoading ? null : onSubmit,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(l10n.sendCodeButton),
          ),
        ],
      ),
    );
  }
}
