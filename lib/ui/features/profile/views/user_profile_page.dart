import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/salesperson.dart';
import '../../../core/cubit/salesperson_cubit.dart';
import '../../../core/theme/app_theme.dart';

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
      body: salesperson == null
          ? Center(
              child: Text(
                'No active session.',
                style: TextStyle(
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ProfileHeader(salesperson: salesperson, isDark: isDark),
                const SizedBox(height: 20),
                _sectionTitle('Contact'),
                const SizedBox(height: 8),
                _infoCard([
                  _infoRow(Icons.phone_outlined, 'Phone',
                      salesperson.phone, isDark),
                  _infoRow(Icons.email_outlined, 'Email',
                      salesperson.email, isDark),
                ]),
                const SizedBox(height: 20),
                _sectionTitle('Assignment'),
                const SizedBox(height: 8),
                _infoCard([
                  _infoRow(Icons.warehouse_outlined, 'Warehouse',
                      salesperson.locationName, isDark),
                  _infoRow(Icons.account_balance_wallet_outlined,
                      'Cash Account', salesperson.cashAccountName, isDark),
                  _infoRow(Icons.tag_outlined, 'Voucher Prefix',
                      salesperson.voucherPrefix, isDark),
                ]),
                const SizedBox(height: 20),
                _sectionTitle('Account'),
                const SizedBox(height: 8),
                _infoCard([
                  _infoRow(Icons.badge_outlined, 'Salesperson ID',
                      salesperson.id, isDark),
                  _statusRow(salesperson.status),
                ]),
                const SizedBox(height: 24),
              ],
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

Widget _statusRow(String status) {
  final isActive = status.toLowerCase() == 'active';
  final color = isActive ? AppTheme.successEmerald : AppTheme.warningAmber;
  return ListTile(
    dense: true,
    leading: Icon(Icons.verified_user_outlined, color: color, size: 20),
    title: const Text('Status', style: TextStyle(fontSize: 13)),
    trailing: Text(
      status,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
    ),
  );
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
