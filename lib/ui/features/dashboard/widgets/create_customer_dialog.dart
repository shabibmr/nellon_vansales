import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/widgets/app_text_field.dart';
import '../../route/bloc/route_bloc.dart';

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
      builder: (_) =>
          CreateCustomerDialog(onCustomerCreated: onCustomerCreated),
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

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final salesRepo = sl<SalesRepository>();
    // Cache these BEFORE any awaits to avoid async-gap BuildContext access
    final routeBloc = context.read<RouteBloc>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final activeRouteId =
        routeBloc.state.activeRouteId ??
        salesRepo.activeRouteId ??
        'route_default';
    final localCustomers = salesRepo.getCustomers();
    final tempId = 'temp_cust_${DateTime.now().millisecondsSinceEpoch}';

    final name = _nameController.text.trim();
    final company = _companyController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();
    final creditLimit =
        double.tryParse(_creditLimitController.text.trim()) ?? 2000.0;

    final newCustomer = Customer(
      id: tempId,
      name: name,
      companyName: company,
      email: email,
      phone: phone,
      address: address,
      outstandingBalance: 0.0,
      creditLimit: creditLimit,
      routeId: activeRouteId,
      sequence: localCustomers.length + 1,
      isPendingSync: true,
    );

    // Persist via the SalesRepository (clean layer boundary)
    await salesRepo.saveCustomers([...localCustomers, newCustomer]);

    // Enqueue for Zoho sync
    final syncItem = SyncQueueItem(
      id: tempId,
      type: 'customer',
      payload: {
        'contact_name': name,
        'company_name': company,
        'email': email,
        'phone': phone,
        'billing_address': {'address': address},
        'route_id': activeRouteId,
        'credit_limit': creditLimit,
        'isPendingSync': true,
      },
      status: SyncStatus.pending,
      timestamp: DateTime.now(),
    );
    await salesRepo.enqueueSyncItem(syncItem);

    if (!mounted) return;

    // Refresh the route list so the new customer appears immediately
    routeBloc.add(LoadRoutes());

    // Fire-and-forget background sync
    sl<SyncWorker>().syncPendingItems();

    setState(() => _isSaving = false);

    navigator.pop(newCustomer);
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.successEmerald,
        content: Text('Customer "$company" created and queued for Zoho sync.'),
      ),
    );

    widget.onCustomerCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

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
                    if (v == null || v.trim().isEmpty)
                      return 'Name is required';
                    if (v.trim().length < 2)
                      return 'Enter at least 2 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _companyController,
                  label: 'Company / Shop Name',
                  icon: Icons.storefront_outlined,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Company name is required';
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
                    if (v == null || v.trim().isEmpty)
                      return 'Phone is required';
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
                    if (!emailRegex.hasMatch(v.trim()))
                      return 'Enter a valid email';
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
                AppTextField(
                  controller: _creditLimitController,
                  label: 'Credit Limit ($cs)',
                  icon: Icons.credit_score_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Credit limit is required';
                    if (double.tryParse(v.trim()) == null)
                      return 'Enter a valid number';
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
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _submit,
          icon: _isSaving
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
  }
}
