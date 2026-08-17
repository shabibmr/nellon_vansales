import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../domain/models/salesperson.dart';
import '../../../core/cubit/salesperson_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/logout.dart';
import '../../app_update/views/developer_channel_sheet.dart';

/// Shows the salesperson session details resolved at login: name, phone,
/// warehouse, cash account, voucher prefix, and status.
class UserProfilePage extends StatelessWidget {
  const UserProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final salesperson = context.watch<SalespersonCubit>().state;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (salesperson == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No active session.',
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ),
                  )
                else ...[
                  _ProfileHeader(salesperson: salesperson, isDark: isDark),
                  const SizedBox(height: 20),
                  _sectionTitle('Contact'),
                  const SizedBox(height: 8),
                  _infoCard([
                    _infoRow(
                      Icons.phone_outlined,
                      'Phone',
                      salesperson.phone,
                      isDark,
                    ),
                    _infoRow(
                      Icons.email_outlined,
                      'Email',
                      salesperson.email,
                      isDark,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _sectionTitle('Assignment'),
                  const SizedBox(height: 8),
                  _infoCard([
                    _infoRow(
                      Icons.warehouse_outlined,
                      'Warehouse',
                      salesperson.locationName,
                      isDark,
                    ),
                    _infoRow(
                      Icons.account_balance_wallet_outlined,
                      'Cash Account',
                      salesperson.cashAccountName,
                      isDark,
                    ),
                    _infoRow(
                      Icons.tag_outlined,
                      'Voucher Prefix',
                      salesperson.voucherPrefix,
                      isDark,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _sectionTitle('Account'),
                  const SizedBox(height: 8),
                  _infoCard([
                    _infoRow(
                      Icons.badge_outlined,
                      'Salesperson ID',
                      salesperson.id,
                      isDark,
                    ),
                    _StatusRow(status: salesperson.status),
                  ]),
                ],
                const SizedBox(height: 20),
                _sectionTitle('Session'),
                const SizedBox(height: 8),
                _infoCard([
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.logout,
                      color: AppTheme.errorRose,
                      size: 20,
                    ),
                    title: const Text(
                      'Log out',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.errorRose,
                      ),
                    ),
                    onTap: () => attemptLogout(context),
                  ),
                ]),
                const SizedBox(height: 20),
                _sectionTitle('App'),
                const SizedBox(height: 8),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    return _infoCard([
                      _infoRow(
                        Icons.info_outline,
                        'Version',
                        info?.version,
                        isDark,
                      ),
                      _infoRow(
                        Icons.numbers_outlined,
                        'Build',
                        info?.buildNumber,
                        isDark,
                      ),
                    ]);
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _sectionTitle(String text) {
  return Text(
    text,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: AppTheme.primaryIndigo,
    ),
  );
}

Widget _infoCard(List<Widget> rows) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(children: rows),
    ),
  );
}

Widget _infoRow(IconData icon, String label, String? value, bool isDark) {
  final secondary =
      isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
  final display = (value == null || value.trim().isEmpty) ? '—' : value;
  return ListTile(
    dense: true,
    leading: Icon(icon, color: AppTheme.primaryIndigo, size: 20),
    title: Text(label, style: const TextStyle(fontSize: 13)),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Text(
        display,
        textAlign: TextAlign.end,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: display == '—' ? secondary : null,
        ),
      ),
    ),
  );
}

class _StatusRow extends StatefulWidget {
  final String status;

  const _StatusRow({required this.status});

  @override
  State<_StatusRow> createState() => _StatusRowState();
}

class _StatusRowState extends State<_StatusRow> {
  int _tapCount = 0;
  DateTime? _lastTapTime;

  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    _lastTapTime = now;

    if (_tapCount == 5) {
      _tapCount = 0;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Developer Mode: Channel Switcher'),
          duration: Duration(seconds: 2),
        ),
      );
      DeveloperChannelSheet.show(context);
    } else if (_tapCount >= 2) {
      final remaining = 5 - _tapCount;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tap $remaining more times for Developer Mode'),
          duration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.status.toLowerCase() == 'active';
    final color = isActive ? AppTheme.successEmerald : AppTheme.warningAmber;
    return InkWell(
      onTap: _handleTap,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.verified_user_outlined, color: color, size: 20),
        title: const Text('Status', style: TextStyle(fontSize: 13)),
        trailing: Text(
          widget.status,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Salesperson salesperson;
  final bool isDark;

  const _ProfileHeader({required this.salesperson, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final initials = salesperson.name.trim().isEmpty
        ? '?'
        : salesperson.name
            .trim()
            .split(RegExp(r'\s+'))
            .map((part) => part[0])
            .take(2)
            .join()
            .toUpperCase();

    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: AppTheme.primaryIndigo,
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                salesperson.name.trim().isEmpty
                    ? 'Unnamed salesperson'
                    : salesperson.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                salesperson.locationName ?? 'No warehouse assigned',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
