import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/customer.dart';
import '../bloc/gps_capture_bloc.dart';
import '../bloc/gps_capture_event.dart';
import '../bloc/gps_capture_state.dart';
import '../theme/app_theme.dart';
import '../utils/permission_dialogs.dart';
import '../utils/snackbars.dart';
import 'app_text_field.dart';

/// Non-blocking prompt that offers to fill in the customer's missing GPS /
/// phone / TRN. Selection always proceeds afterward — SAVE, SKIP, and
/// dismissing (tap outside / back button) all resolve to a [Customer]; GPS
/// captured with an accurate fix is persisted immediately regardless of how
/// the dialog is closed, since it's saved the moment it's captured.
Future<Customer> showCustomerMissingFieldsDialog(
  BuildContext context, {
  required GpsCaptureBloc gpsBloc,
  required Customer customer,
}) async {
  final missing = CustomerMissingFields.of(customer);
  if (!missing.any) return customer;

  final result = await showDialog<Customer>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) => BlocProvider.value(
      value: gpsBloc,
      child: CustomerMissingFieldsDialog(customer: customer, missing: missing),
    ),
  );
  return result ?? customer;
}

class CustomerMissingFieldsDialog extends StatefulWidget {
  final Customer customer;
  final CustomerMissingFields missing;

  const CustomerMissingFieldsDialog({
    super.key,
    required this.customer,
    required this.missing,
  });

  @override
  State<CustomerMissingFieldsDialog> createState() =>
      _CustomerMissingFieldsDialogState();
}

class _CustomerMissingFieldsDialogState
    extends State<CustomerMissingFieldsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController;
  late final TextEditingController _trnController;
  late Customer _customer;
  late bool _gpsFilled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _gpsFilled = !widget.missing.gps;
    _phoneController = TextEditingController(
      text: widget.missing.phone ? '' : widget.customer.phone,
    );
    _trnController = TextEditingController(
      text: widget.missing.trn ? '' : widget.customer.trn,
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _trnController.dispose();
    super.dispose();
  }

  bool get _needsTextFields => widget.missing.phone || widget.missing.trn;

  bool get _phoneReady {
    if (!widget.missing.phone) return true;
    return _isValidPhone(_phoneController.text);
  }

  bool get _trnReady {
    if (!widget.missing.trn) return true;
    return _isValidTrn(_trnController.text);
  }

  bool get _canComplete => _phoneReady && _trnReady;

  static bool _isValidPhone(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7;
  }

  static bool _isValidTrn(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'\D'), '');
    return digits.length == 15;
  }

  void _onGpsSuccess(GpsCaptureSuccess state) {
    final enriched =
        state.enrichedCustomer ??
        _customer.copyWith(
          latitude: state.latitude,
          longitude: state.longitude,
        );
    setState(() {
      _customer = enriched;
      _gpsFilled = true;
    });
  }

  /// SAVE only persists phone/TRN — GPS is already persisted (see
  /// [_onGpsSuccess]) the moment an accurate fix is captured.
  Future<void> _complete() async {
    if (_saving || !_canComplete) return;
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _saving = true);
    final bloc = context.read<GpsCaptureBloc>();
    final phone = widget.missing.phone ? _phoneController.text.trim() : null;
    final trn = widget.missing.trn
        ? _trnController.text.trim().replaceAll(RegExp(r'\D'), '')
        : null;

    final resultFuture = bloc.stream.firstWhere(
      (s) => s is ContactFieldsSaved || s is ContactFieldsSaveFailure,
    );
    bloc.add(
      ContactFieldsSaveRequested(customer: _customer, phone: phone, trn: trn),
    );
    final state = await resultFuture;

    if (!mounted) return;
    if (state is ContactFieldsSaved) {
      Navigator.of(context).pop(state.enrichedCustomer);
    } else {
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Could not save customer details.');
    }
  }

  /// Close without persisting typed text; any GPS already captured (and
  /// therefore already persisted) is retained.
  void _skip() {
    Navigator.of(context).pop(_customer);
  }

  @override
  Widget build(BuildContext context) {
    final missing = widget.missing;

    return BlocListener<GpsCaptureBloc, GpsCaptureState>(
      listenWhen: (prev, curr) =>
          curr is GpsCaptureSuccess ||
          curr is GpsCaptureInaccurate ||
          curr is GpsCapturePermissionDenied ||
          curr is GpsCaptureServiceDisabled ||
          curr is GpsCaptureFailure,
      listener: (ctx, state) {
        if (state is GpsCaptureSuccess) {
          _onGpsSuccess(state);
        } else if (state is GpsCaptureInaccurate) {
          showErrorSnackBar(
            context,
            'GPS accuracy too low (±${state.accuracy.toStringAsFixed(0)}m) — try again outdoors.',
          );
        } else if (state is GpsCapturePermissionDenied) {
          showLocationPermissionSettingsDialog(context);
        } else if (state is GpsCaptureServiceDisabled) {
          showEnableLocationServiceDialog(context);
        } else if (state is GpsCaptureFailure) {
          showErrorSnackBar(context, 'Capture failed: ${state.message}');
        }
      },
      child: BlocBuilder<GpsCaptureBloc, GpsCaptureState>(
        builder: (ctx, gpsState) {
          final capturing = gpsState is GpsCaptureInProgress;
          final busy = capturing || _saving;

          return AlertDialog(
            title: Text(missing.dialogTitle),
            content: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_customer.name} (${_customer.companyName})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_introCopy(missing)),
                    if (missing.gps) ...[
                      const SizedBox(height: 16),
                      _GpsSection(
                        filled: _gpsFilled,
                        customer: _customer,
                        capturing: capturing,
                        enabled: !busy,
                        onCapture: () => ctx.read<GpsCaptureBloc>().add(
                          GpsCaptureRequested(
                            customer: _customer,
                            persist: true,
                          ),
                        ),
                      ),
                    ],
                    if (missing.phone) ...[
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _phoneController,
                        label: 'Phone Number',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        autofocus: !missing.gps,
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (!_isValidPhone(v ?? '')) {
                            return 'Enter a valid phone number';
                          }
                          return null;
                        },
                      ),
                    ],
                    if (missing.trn) ...[
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _trnController,
                        label: 'TRN Number',
                        icon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        autofocus: !missing.gps && !missing.phone,
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (!_isValidTrn(v ?? '')) {
                            return 'Enter a 15-digit TRN';
                          }
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : _skip,
                child: const Text('SKIP'),
              ),
              // GPS already persists the moment it's captured — SAVE only
              // has work to do (and is only shown) when phone/TRN are typed.
              if (_needsTextFields)
                FilledButton.icon(
                  onPressed: busy || !_canComplete ? null : _complete,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('SAVE'),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _introCopy(CustomerMissingFields missing) {
    final parts = <String>[
      if (missing.gps) 'GPS location',
      if (missing.phone) 'phone number',
      if (missing.trn) 'TRN number',
    ];
    if (parts.length == 1) {
      if (missing.gps) {
        return 'This customer has no GPS location yet. Capture the current device location, or skip and add it later.';
      }
      if (missing.phone) {
        return 'This customer has no phone number on file. Enter it now, or skip and add it later.';
      }
      return 'This customer has no TRN on file. Enter the 15-digit tax registration number, or skip and add it later.';
    }
    final last = parts.removeLast();
    return 'This customer is missing ${parts.join(', ')} and $last. Fill in the details, or skip and add them later.';
  }
}

class _GpsSection extends StatelessWidget {
  final bool filled;
  final Customer customer;
  final bool capturing;
  final bool enabled;
  final VoidCallback onCapture;

  const _GpsSection({
    required this.filled,
    required this.customer,
    required this.capturing,
    required this.enabled,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      final lat = customer.latitude?.toStringAsFixed(5) ?? '';
      final lng = customer.longitude?.toStringAsFixed(5) ?? '';
      return Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppTheme.successEmerald,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'GPS captured: $lat, $lng',
              style: const TextStyle(color: AppTheme.successEmerald),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: enabled && !capturing ? onCapture : null,
        icon: capturing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.gps_fixed),
        label: const Text('CAPTURE GPS'),
      ),
    );
  }
}
