import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/snackbars.dart';
import '../cubit/server_config_cubit.dart';
import '../cubit/server_config_state.dart';

/// Drawer tile that toggles all Zoho transaction mock flags at once.
class MockLiveSwitchTile extends StatelessWidget {
  const MockLiveSwitchTile({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerConfigCubit, ServerConfigState>(
      builder: (context, state) {
        final apiClient = sl<ZohoApiClient>();
        final credentialsLocked = apiClient.usesPlaceholderCredentials;
        final isLive = !state.isMockModeEnabled;

        return SwitchListTile(
          secondary: Icon(
            isLive ? Icons.cloud_upload_outlined : Icons.science_outlined,
            color: isLive ? AppTheme.successEmerald : AppTheme.warningAmber,
          ),
          title: const Text('Transaction Sync'),
          subtitle: Text(
            credentialsLocked
                ? 'Placeholder credentials — mock only'
                : (isLive
                      ? 'Live — uploads push to Zoho'
                      : 'Mock — uploads are simulated'),
            style: TextStyle(
              fontSize: 12,
              color: isLive ? AppTheme.successEmerald : AppTheme.warningAmber,
            ),
          ),
          value: isLive,
          onChanged: credentialsLocked
              ? null
              : (live) async {
                  await context.read<ServerConfigCubit>().setMockModeEnabled(
                    !live,
                  );
                  if (!context.mounted) return;
                  showSuccessSnackBar(
                    context,
                    live
                        ? 'Live mode — transactions will push to Zoho'
                        : 'Mock mode — transactions are simulated',
                  );
                },
        );
      },
    );
  }
}