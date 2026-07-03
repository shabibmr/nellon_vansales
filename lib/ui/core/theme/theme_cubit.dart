import 'package:flutter_bloc/flutter_bloc.dart';

enum AppThemeMode { light, dark, glass }

/// Cubit managing the active user interface theme mode state.
///
/// Permits on-the-fly cycling between [AppThemeMode.light], [AppThemeMode.dark], and [AppThemeMode.glass].
class ThemeCubit extends Cubit<AppThemeMode> {
  /// Instantiates a new [ThemeCubit] defaulting to [AppThemeMode.light].
  ThemeCubit() : super(AppThemeMode.light);

  /// Cycles the theme: light → dark → glass → light.
  void toggleTheme() {
    switch (state) {
      case AppThemeMode.light:
        emit(AppThemeMode.dark);
      case AppThemeMode.dark:
        emit(AppThemeMode.glass);
      case AppThemeMode.glass:
        emit(AppThemeMode.light);
    }
  }
}
