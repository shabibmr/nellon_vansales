import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/app_update_cubit.dart';
import '../cubit/app_update_state.dart';
import 'app_update_dialog.dart';
import 'app_update_force_screen.dart';

/// Top-level listener: live Firestore watch, force-update gate, optional dialog.
class AppUpdateGate extends StatefulWidget {
  final Widget child;

  const AppUpdateGate({super.key, required this.child});

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _optionalDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppUpdateCubit>().startWatching();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final cubit = context.read<AppUpdateCubit>();
    if (cubit.isInFlight) return;
    cubit.checkForUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AppUpdateCubit, AppUpdateState>(
      listener: (context, state) {
        if (state is AppUpdateAvailable &&
            !state.updateInfo.forceUpdate &&
            !_optionalDialogShowing) {
          _optionalDialogShowing = true;
          AppUpdateDialog.show(context, state.updateInfo).then((_) {
            _optionalDialogShowing = false;
          });
        }
      },
      builder: (context, state) {
        if (state.isForceBlocking) {
          return AppUpdateForceScreen(updateInfo: state.updateInfo!);
        }
        return widget.child;
      },
    );
  }
}
