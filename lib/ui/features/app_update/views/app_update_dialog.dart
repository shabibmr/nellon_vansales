import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../domain/models/app_update_info.dart';
import '../cubit/app_update_cubit.dart';
import 'app_update_panel.dart';

/// Optional (non-forced) update prompt. Dismissible via Later or the barrier.
class AppUpdateDialog extends StatelessWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (dialogCtx) => PopScope(
        canPop: !info.forceUpdate,
        child: BlocProvider.value(
          value: context.read<AppUpdateCubit>(),
          child: AppUpdateDialog(updateInfo: info),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
            onLater: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}
