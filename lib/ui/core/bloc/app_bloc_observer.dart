import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/app_logger.dart';

/// Logs BLoC errors through [AppLogger] (Crashlytics in production).
class AppBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    AppLogger.error(
      'Bloc',
      '${bloc.runtimeType}: $error',
      error,
      stackTrace,
    );
    super.onError(bloc, error, stackTrace);
  }
}
