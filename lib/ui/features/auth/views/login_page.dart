import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';

/// The Login Screen of the Van Sales application.
///
/// Implements beautiful glassmorphism gradients, input forms with field validation, 
/// and maps submittals directly to the [AuthBloc] trigger.
class LoginPage extends StatefulWidget {
  /// Creates a new [LoginPage].
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'agent@nellon.com');
  final _passwordController = TextEditingController(text: 'Password123');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Triggers credential validation and fires [LoginRequested] event to Auth Bloc.
  void _onSubmit() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
            LoginRequested(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Stunning Gradient Backdrop
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF0F172A), const Color(0xFF1E1E38), const Color(0xFF110E24)]
                    : [const Color(0xFFEEF2F6), const Color(0xFFE0E7FF), const Color(0xFFEEF2F6)],
              ),
            ),
          ),
          
          // Subtle glow decorations (glassmorphic aesthetic)
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

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Icon & Header
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 64,
                      color: AppTheme.primaryIndigo,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'VAN SALES PRO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Predefined Routes & Zoho Books Integration',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Premium Card Container
                    Card(
                      elevation: isDark ? 0 : 8,
                      child: Padding(
                        padding: const EdgeInsets.all(28.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Agent Sign In',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Email Input
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email Address',
                                  hintText: 'name@company.com',
                                  prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryIndigo),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Invalid email format';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              // Password Input
                              TextFormField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  hintText: '••••••••',
                                  prefixIcon: Icon(Icons.lock_outlined, color: AppTheme.primaryIndigo),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),

                              // Error Notification State
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, state) {
                                  if (state is AuthFailure) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppTheme.errorRose.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: AppTheme.errorRose.withValues(alpha: 0.3), width: 1),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.error_outline, color: AppTheme.errorRose, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                state.message,
                                                style: const TextStyle(
                                                  color: Colors.redAccent,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),

                              // Submit Button with loading animation
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, state) {
                                  final isLoading = state is AuthLoading;
                                  return ElevatedButton(
                                    onPressed: isLoading ? null : _onSubmit,
                                    child: isLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('SIGN IN'),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
