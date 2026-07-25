import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/permission_dialogs.dart';
import '../../../core/utils/snackbars.dart';
import '../../thermal_print/cubit/thermal_printer_cubit.dart';
import '../../thermal_print/cubit/thermal_printer_state.dart';
import '../../../../domain/models/thermal_paper_size.dart';

/// App settings: thermal printer paper size, pairing, and test print.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    context.read<ThermalPrinterCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: BlocConsumer<ThermalPrinterCubit, ThermalPrinterState>(
        listenWhen: (prev, curr) =>
            prev.errorMessage != curr.errorMessage ||
            prev.statusMessage != curr.statusMessage ||
            prev.needsAppSettings != curr.needsAppSettings,
        listener: (context, state) {
          if (state.needsAppSettings) {
            showBluetoothPermissionSettingsDialog(context);
            context.read<ThermalPrinterCubit>().clearNeedsAppSettings();
            // Still surface the short error if present.
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context.read<ThermalPrinterCubit>().clearMessages();
            }
            return;
          }
          if (state.errorMessage != null) {
            showErrorSnackBar(context, state.errorMessage!);
            context.read<ThermalPrinterCubit>().clearMessages();
          } else if (state.statusMessage != null) {
            showSuccessSnackBar(context, state.statusMessage!);
            context.read<ThermalPrinterCubit>().clearMessages();
          }
        },
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('Thermal printer'),
              const SizedBox(height: 8),
              Text(
                'Match paper size to the roll loaded in the printer '
                '(Nigachi NC-MTP500 series).',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _sectionTitle('Paper size'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<ThermalPaperSize>(
                        segments: const [
                          ButtonSegment(
                            value: ThermalPaperSize.inch4,
                            label: Text('4 inches'),
                            icon: Icon(Icons.crop_landscape, size: 18),
                          ),
                          ButtonSegment(
                            value: ThermalPaperSize.inch2,
                            label: Text('2 inches'),
                            icon: Icon(Icons.crop_portrait, size: 18),
                          ),
                        ],
                        selected: {state.paperSize},
                        onSelectionChanged: state.isLoading || state.isPrinting
                            ? null
                            : (selection) {
                                if (selection.isNotEmpty) {
                                  context
                                      .read<ThermalPrinterCubit>()
                                      .setPaperSize(selection.first);
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.paperSize == ThermalPaperSize.inch4
                            ? 'Default — full width (NC-MTP500 class)'
                            : 'Narrow 58mm rolls',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Bluetooth printer'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _statusRow(
                        'Bluetooth',
                        state.bluetoothOn ? 'On' : 'Off',
                        state.bluetoothOn
                            ? AppTheme.successEmerald
                            : AppTheme.errorRose,
                      ),
                      const SizedBox(height: 6),
                      _statusRow(
                        'Permission',
                        state.permissionGranted ? 'Granted' : 'Needed',
                        state.permissionGranted
                            ? AppTheme.successEmerald
                            : AppTheme.warningAmber,
                      ),
                      const SizedBox(height: 6),
                      _statusRow(
                        'Connection',
                        state.isConnected ? 'Connected' : 'Disconnected',
                        state.isConnected
                            ? AppTheme.successEmerald
                            : AppTheme.darkTextSecondary,
                      ),
                      if (state.preferredPrinter != null) ...[
                        const SizedBox(height: 6),
                        _statusRow(
                          'Preferred',
                          state.preferredPrinter!.name,
                          AppTheme.primaryIndigo,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (!state.permissionGranted)
                            OutlinedButton.icon(
                              onPressed: state.isLoading
                                  ? null
                                  : () => context
                                      .read<ThermalPrinterCubit>()
                                      .requestPermission(),
                              icon: const Icon(Icons.security, size: 18),
                              label: const Text('Allow Bluetooth'),
                            ),
                          OutlinedButton.icon(
                            onPressed: state.isLoading
                                ? null
                                : () => context
                                    .read<ThermalPrinterCubit>()
                                    .refresh(),
                            icon: state.isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh, size: 18),
                            label: const Text('Refresh devices'),
                          ),
                          if (state.isConnected)
                            OutlinedButton.icon(
                              onPressed: state.isLoading
                                  ? null
                                  : () => context
                                      .read<ThermalPrinterCubit>()
                                      .disconnect(),
                              icon: const Icon(Icons.link_off, size: 18),
                              label: const Text('Disconnect'),
                            ),
                          if (state.preferredPrinter != null)
                            OutlinedButton.icon(
                              onPressed: state.isLoading
                                  ? null
                                  : () => context
                                      .read<ThermalPrinterCubit>()
                                      .forgetPrinter(),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Forget'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (state.bondedDevices.isEmpty &&
                  state.permissionGranted &&
                  state.bluetoothOn &&
                  !state.isLoading)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No bonded printers found. Pair your NC-MTP500 (or other ESC/POS printer) in Android Bluetooth settings, then tap Refresh.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ),
                ),
              ...state.bondedDevices.map((device) {
                final isPreferred =
                    state.preferredPrinter?.macAddress == device.macAddress;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.print,
                      color: isPreferred
                          ? AppTheme.primaryIndigo
                          : (isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary),
                    ),
                    title: Text(device.name),
                    subtitle: Text(device.macAddress),
                    trailing: isPreferred
                        ? const Icon(
                            Icons.check_circle,
                            color: AppTheme.successEmerald,
                          )
                        : TextButton(
                            onPressed: state.isLoading || state.isPrinting
                                ? null
                                : () => context
                                    .read<ThermalPrinterCubit>()
                                    .selectPrinter(device),
                            child: const Text('Use'),
                          ),
                    onTap: state.isLoading || state.isPrinting
                        ? null
                        : () => context
                            .read<ThermalPrinterCubit>()
                            .selectPrinter(device),
                  ),
                );
              }),
              const SizedBox(height: 24),
              _sectionTitle('Confirm setup'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Send a short calibration ticket using the selected '
                        'paper size (${state.paperSize.label}). Use this to '
                        'confirm Bluetooth and layout before printing vouchers.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: state.isPrinting || state.isLoading
                            ? null
                            : () => context
                                .read<ThermalPrinterCubit>()
                                .printTestPage(),
                        icon: state.isPrinting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.receipt_long),
                        label: Text(
                          state.isPrinting
                              ? 'Printing test page…'
                              : 'Test print',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryIndigo,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      if (state.preferredPrinter == null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Tip: select a printer above first (or pair it in '
                          'Android Bluetooth settings).',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
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

  Widget _statusRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
