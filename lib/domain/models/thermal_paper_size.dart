/// Selectable thermal roll width for ESC/POS ticket layout.
///
/// Persisted in Settings. Default is [inch4] for Nigachi NC-MTP500 class printers.
enum ThermalPaperSize {
  /// ~112mm / 4-inch class (default). Mapped to wide ESC/POS profile (~48 cols).
  inch4,

  /// ~58mm / 2-inch rolls (~32 cols Font A).
  inch2,
}

extension ThermalPaperSizeX on ThermalPaperSize {
  /// User-facing label for Settings UI.
  String get label => switch (this) {
        ThermalPaperSize.inch4 => '4 inches',
        ThermalPaperSize.inch2 => '2 inches',
      };

  /// Short label for test-print banner.
  String get shortLabel => switch (this) {
        ThermalPaperSize.inch4 => '4"',
        ThermalPaperSize.inch2 => '2"',
      };

  /// Approximate Font A columns used by ticket builders.
  int get columns => switch (this) {
        ThermalPaperSize.inch4 => 48,
        ThermalPaperSize.inch2 => 32,
      };

  /// Hive / prefs wire value.
  String get storageKey => switch (this) {
        ThermalPaperSize.inch4 => 'inch4',
        ThermalPaperSize.inch2 => 'inch2',
      };

  static ThermalPaperSize fromStorageKey(String? key) {
    return switch (key) {
      'inch2' => ThermalPaperSize.inch2,
      _ => ThermalPaperSize.inch4,
    };
  }
}
