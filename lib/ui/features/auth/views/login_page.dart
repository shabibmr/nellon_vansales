import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/extensions/l10n_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/widgets/app_logo.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/login_otp_step.dart';
import '../widgets/login_phone_step.dart';

/// The Login Screen of the Van Sales application.
///
/// Two-step Firebase Phone OTP flow: enter a mobile number in international
/// format, then enter the SMS code. The active step is driven by [AuthBloc] state so Android
/// auto-verification (which can complete before or without a code-entry
/// step) is reflected correctly regardless of local UI state.
class LoginPage extends StatefulWidget {
  /// Creates a new [LoginPage].
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  Timer? _resendTimer;
  int _resendSecondsLeft = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendSecondsLeft -= 1;
        if (_resendSecondsLeft <= 0) timer.cancel();
      });
    });
  }

  void _onPhoneSubmit() {
    if (!_phoneFormKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(PhoneSubmitted(_phoneController.text.trim()));
  }

  void _onOtpSubmit() {
    final code = _otpController.text.trim();
    if (code.length != 6) return;
    context.read<AuthBloc>().add(OtpSubmitted(code));
  }

  void _onResend() {
    context.read<AuthBloc>().add(OtpResendRequested());
    _startResendCooldown();
  }

  void _onChangeNumber() {
    _otpController.clear();
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = 0);
    context.read<AuthBloc>().add(OtpAborted());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthCodeSent) {
            _otpController.clear();
            if (_resendSecondsLeft == 0 || state.autoRetrievalTimedOut) {
              if (state.autoRetrievalTimedOut) {
                _resendTimer?.cancel();
                setState(() => _resendSecondsLeft = 0);
              } else {
                _startResendCooldown();
              }
            }
          } else if (state is AuthFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          } else if (state is Unauthenticated) {
            _otpController.clear();
          }
        },
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF0F172A),
                          const Color(0xFF1E1E38),
                          const Color(0xFF110E24),
                        ]
                      : [
                          const Color(0xFFEEF2F6),
                          const Color(0xFFE0E7FF),
                          const Color(0xFFEEF2F6),
                        ],
                ),
              ),
            ),
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryIndigo.withValues(alpha: 0.15),
                      blurRadius: 100,
                      spreadRadius: 50,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.infoSky.withValues(alpha: 0.1),
                      blurRadius: 80,
                      spreadRadius: 40,
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: AppLogo(size: 88, showShadow: true),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          context.l10n.brandName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.brandSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Card(
                          elevation: isDark ? 0 : 8,
                          child: Padding(
                            padding: const EdgeInsets.all(28.0),
                            child: BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, state) {
                                final showOtpStep =
                                    state is AuthCodeSent ||
                                    state is AuthVerifyingOtp;
                                return showOtpStep
                                    ? LoginOtpStep(
                                        otpController: _otpController,
                                        phone: state is AuthCodeSent
                                            ? state.phone
                                            : state is AuthVerifyingOtp
                                            ? state.phone
                                            : _phoneController.text,
                                        state: state,
                                        resendSecondsLeft: _resendSecondsLeft,
                                        onSubmit: _onOtpSubmit,
                                        onResend: _onResend,
                                        onChangeNumber: _onChangeNumber,
                                      )
                                    : LoginPhoneStep(
                                        formKey: _phoneFormKey,
                                        phoneController: _phoneController,
                                        state: state,
                                        onSubmit: _onPhoneSubmit,
                                      );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
