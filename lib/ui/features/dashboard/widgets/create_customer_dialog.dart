import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/app_text_field.dart';
import '../../../../ui/core/bloc/gps_capture_bloc.dart';
import '../../../../ui/core/bloc/gps_capture_event.dart';
import '../../../../ui/core/bloc/gps_capture_state.dart';
import '../../route/bloc/route_bloc.dart';
import '../cubit/create_customer_cubit.dart';
import '../cubit/create_customer_state.dart';

/// Modal dialog for logging a new customer offline on the route.
///
/// Prompts fields for customer display name, company name, address, email, phone, and credit parameters.
/// Instantly saves a local client record with a temporary client ID and pushes an upload job to the Sync Queue.
class CreateCustomerDialog extends StatefulWidget {
  /// Optional callback triggered when the customer creation transaction successfully completes.
  final VoidCallback? onCustomerCreated;

  /// Creates a new [CreateCustomerDialog].
  const CreateCustomerDialog({super.key, this.onCustomerCreated});

  /// Presents the dialog and resolves to the newly created [Customer], or
  /// `null` if the user cancelled.
  static Future<Customer?> show(
    BuildContext context, {
    VoidCallback? onCustomerCreated,
  }) {
    return showDialog<Customer>(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<GpsCaptureBloc>(
            create: (_) => GpsCaptureBloc(
              salesRepository: sl<SalesRepository>(),
              zohoApiClient: sl<ZohoApiClient>(),
              syncWorker: sl<SyncWorker>(),
            ),
          ),
          BlocProvider<CreateCustomerCubit>(
            create: (_) => CreateCustomerCubit(
              salesRepository: sl<SalesRepository>(),
            ),
          ),
        ],
        child: CreateCustomerDialog(onCustomerCreated: onCustomerCreated),
      ),
    );
  }

  @override
  State<CreateCustomerDialog> createState() => _CreateCustomerDialogState();
}

class _CreateCustomerDialogState extends State<CreateCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _creditLimitController = TextEditingController(text: '2000');
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _creditLimitController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final salesRepo = sl<SalesRepository>();
    final routeBloc = context.read<RouteBloc>();
    final activeRouteId =
        routeBloc.state.activeRouteId ??
        salesRepo.activeRouteId ??
        'route_default';

    final name = _nameController.text.trim();
    final company = _companyController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();
    final creditLimit =
        double.tryParse(_creditLimitController.text.trim()) ?? 2000.0;

    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());

    context.read<CreateCustomerCubit>().submit(
          name: name,
          company: company,
          email: email,
          phone: phone,
          address: address,
          creditLimit: creditLimit,
          activeRouteId: activeRouteId,
          latitude: lat,
          longitude: lng,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return MultiBlocListener(
      listeners: [
        BlocListener<GpsCaptureBloc, GpsCaptureState>(
          listener: (context, state) {
            if (state is GpsCaptureSuccess) {
              _latController.text = state.latitude.toStringAsFixed(6);
              _lngController.text = state.longitude.toStringAsFixed(6);
              showSuccessSnackBar(
                context,
                'GPS captured: ${state.latitude.toStringAsFixed(4)}, ${state.longitude.toStringAsFixed(4)}',
              );
            } else if (state is GpsCapturePermissionDenied) {
              showErrorSnackBar(
                context,
                'Location permission denied. You can enter coordinates manually.',
              );
            } else if (state is GpsCaptureServiceDisabled) {
              showErrorSnackBar(
                context,
                'Location services are disabled on this device.',
              );
            } else if (state is GpsCaptureFailure) {
              showErrorSnackBar(context, 'Failed to get location: ${state.message}');
            }
          },
        ),
        BlocListener<CreateCustomerCubit, CreateCustomerState>(
          listener: (context, state) {
            if (state is CreateCustomerSuccess) {
              context.read<RouteBloc>().add(LoadRoutes());
              sl<SyncWorker>().syncPendingItems();
              Navigator.of(context).pop(state.customer);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.successEmerald,
                  content: Text('Customer "${state.customer.companyName}" created and queued for Zoho sync.'),
                ),
              );
              widget.onCustomerCreated?.call();
            } else if (state is CreateCustomerFailure) {
              showErrorSnackBar(context, 'Failed to save customer: ${state.message}');
            }
          },
        ),
      ],
      child: BlocBuilder<CreateCustomerCubit, CreateCustomerState>(
        builder: (context, createCustomerState) {
          final isSaving = createCustomerState is CreateCustomerSaving;

          return BlocBuilder<GpsCaptureBloc, GpsCaptureState>(
            builder: (context, gpsState) {
              final isCapturingGps = gpsState is GpsCaptureInProgress;

              return AlertDialog(
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryIndigo.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_add_rounded,
                        color: AppTheme.primaryIndigo,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'New Customer',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppTextField(
                            controller: _nameController,
                            label: 'Full Contact Name',
                            icon: Icons.person_outline_rounded,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Name is required';
                              }
                              if (v.trim().length < 2) {
                                return 'Enter at least 2 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          AppTextField(
                            controller: _companyController,
                            label: 'Company / Shop Name',
                            icon: Icons.storefront_outlined,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Company name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          AppTextField(
                            controller: _phoneController,
                            label: 'Phone Number',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Phone is required';
                              }
                              final digits = v.trim().replaceAll(RegExp(r'\D'), '');
                              if (digits.length < 7) return 'Enter a valid phone number';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          AppTextField(
                            controller: _emailController,
                            label: 'Email Address (optional)',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final emailRegex = RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$');
                              if (!emailRegex.hasMatch(v.trim())) {
                                    return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          AppTextField(
                            controller: _addressController,
                            label: 'Billing Address',
                            icon: Icons.location_on_outlined,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),

                          // GPS section (supports on-the-fly capture for new customers)
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  controller: _latController,
                                  label: 'Latitude (optional)',
                                  icon: Icons.my_location,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppTextField(
                                  controller: _lngController,
                                  label: 'Longitude (optional)',
                                  icon: Icons.my_location,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: isCapturingGps || isSaving
                                  ? null
                                  : () => context.read<GpsCaptureBloc>().add(
                                        const GpsCaptureRequested(persist: false),
                                      ),
                              icon: isCapturingGps
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.gps_fixed, size: 18),
                              label: const Text('CAPTURE CURRENT LOCATION'),
                            ),
                          ),
                          const SizedBox(height: 6),

                          AppTextField(
                            controller: _creditLimitController,
                            label: 'Credit Limit ($cs)',
                            icon: Icons.credit_score_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Credit limit is required';
                              }
                              if (double.tryParse(v.trim()) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving ? null : () => Navigator.pop(context),
                    child: const Text('CANCEL'),
                  ),
                  FilledButton.icon(
                    onPressed: isSaving ? null : _submit,
                    icon: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('CREATE'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
