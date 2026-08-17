import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../domain/models/app_update_info.dart';
import '../cubit/app_update_cubit.dart';
import '../cubit/app_update_state.dart';
import 'app_update_panel.dart';

/// Optional (non-forced) update prompt. Dismissible via Later button when not downloading.
class AppUpdateDialog extends StatelessWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => BlocProvider.value(
        value: context.read<AppUpdateCubit>(),
        child: AppUpdateDialog(updateInfo: info),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppUpdateCubit, AppUpdateState>(
      builder: (context, state) {
        final isBusy =
            state is AppUpdateDownloading || state is AppUpdateInstalling;
        final canDismiss = !updateInfo.forceUpdate && !isBusy;

        return PopScope(
          canPop: canDismiss,
          child: Dialog(
            backgroundColor: AppTheme.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppTheme.glassBorder, width: 1),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 480,
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: AppUpdatePanel(
                  updateInfo: updateInfo,
                  onLater: canDismiss ? () => Navigator.of(context).pop() : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
