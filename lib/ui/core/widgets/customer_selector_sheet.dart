import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/models/customer.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../../../data/services/injection.dart';
import '../../../data/services/sync_worker.dart';
import '../../../data/services/zoho_api_client.dart';
import '../theme/app_theme.dart';
import '../extensions/org_context_extension.dart';
import '../utils/currency.dart';
import '../utils/snackbars.dart';
import '../cubit/list_filter_cubit.dart';
import '../bloc/gps_capture_bloc.dart';
import '../bloc/gps_capture_event.dart';
import '../bloc/gps_capture_state.dart';

/// Generic customer-selector bottom sheet shared by all editor flows.
class CustomerSelectorSheet extends StatelessWidget {
  final List<Customer> customers;
  final void Function(Customer) onSelected;
  final bool showCreateOption;
  final String createOptionSubtitle;
  final Color accentColor;
  final Future<void> Function()? onCreateTap;

  const CustomerSelectorSheet({
    super.key,
    required this.customers,
    required this.onSelected,
    this.showCreateOption = false,
    this.createOptionSubtitle = 'Add a new customer',
    this.accentColor = AppTheme.primaryIndigo,
    this.onCreateTap,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Customer> customers,
    required void Function(Customer) onSelected,
    bool showCreateOption = false,
    String createOptionSubtitle = 'Add a new customer',
    Color accentColor = AppTheme.primaryIndigo,
    Future<void> Function()? onCreateTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => MultiBlocProvider(
        providers: [
          BlocProvider<ListFilterCubit<Customer>>(
            create: (_) => ListFilterCubit<Customer>(
              initialItems: customers,
              filterPredicate: (c, query) {
                final q = query.toLowerCase();
                return c.name.toLowerCase().contains(q) ||
                    c.companyName.toLowerCase().contains(q) ||
                    c.phone.contains(q);
              },
            ),
          ),
          BlocProvider<GpsCaptureBloc>(
            create: (_) => GpsCaptureBloc(
              salesRepository: sl<SalesRepository>(),
              zohoApiClient: sl<ZohoApiClient>(),
              syncWorker: sl<SyncWorker>(),
            ),
          ),
        ],
        child: CustomerSelectorSheet(
          customers: customers,
          onSelected: onSelected,
          showCreateOption: showCreateOption,
          createOptionSubtitle: createOptionSubtitle,
          accentColor: accentColor,
          onCreateTap: onCreateTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CustomerSelectorSheetBody(
      onSelected: onSelected,
      showCreateOption: showCreateOption,
      createOptionSubtitle: createOptionSubtitle,
      accentColor: accentColor,
      onCreateTap: onCreateTap,
    );
  }
}

class _CustomerSelectorSheetBody extends StatefulWidget {
  final void Function(Customer) onSelected;
  final bool showCreateOption;
  final String createOptionSubtitle;
  final Color accentColor;
  final Future<void> Function()? onCreateTap;

  const _CustomerSelectorSheetBody({
    required this.onSelected,
    required this.showCreateOption,
    required this.createOptionSubtitle,
    required this.accentColor,
    this.onCreateTap,
  });

  @override
  State<_CustomerSelectorSheetBody> createState() =>
      _CustomerSelectorSheetBodyState();
}

class _CustomerSelectorSheetBodyState extends State<_CustomerSelectorSheetBody> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    // Lift the sheet above the soft keyboard so the search field stays at the
    // top and the results list remains visible (not covered mid-sheet).
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select Customer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (val) => context
                      .read<ListFilterCubit<Customer>>()
                      .setQuery(val),
                  decoration: InputDecoration(
                    hintText: 'Search by name, company or phone...',
                    prefixIcon:
                        Icon(Icons.search, color: widget.accentColor),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              if (widget.showCreateOption) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_add_rounded,
                      color: widget.accentColor,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Create New Customer',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.accentColor,
                    ),
                  ),
                  subtitle: Text(widget.createOptionSubtitle),
                  onTap: () async {
                    Navigator.pop(context);
                    await widget.onCreateTap?.call();
                  },
                ),
                const Divider(height: 1),
              ],
              Expanded(
                child: BlocBuilder<ListFilterCubit<Customer>,
                    ListFilterState<Customer>>(
                  builder: (context, state) {
                    final filtered = state.filteredItems;

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          'No customers found',
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = filtered[index];
                        return ListTile(
                          title: Text(
                            customer.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            _customerAddressOrLocation(customer),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: false,
                          trailing: customer.outstandingBalance > 0
                              ? Text(
                                  'Outstanding: ${formatCurrency(customer.outstandingBalance, cs)}',
                                  style: const TextStyle(
                                    color: AppTheme.errorRose,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                          onTap: () async {
                            final navigator = Navigator.of(context);
                            final gpsBloc = context.read<GpsCaptureBloc>();
                            Customer toSelect = customer;

                            if (customer.latitude == null ||
                                customer.longitude == null) {
                              final enriched = await _showGpsCapturePrompt(
                                context,
                                gpsBloc,
                                customer,
                                isDark,
                              );
                              if (enriched != null) {
                                toSelect = enriched;
                              }
                            }

                            widget.onSelected(toSelect);
                            navigator.pop();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Prefer street [Customer.address]; fall back to GPS coordinates, then company.
String _customerAddressOrLocation(Customer customer) {
  final address = customer.address.trim();
  if (address.isNotEmpty) return address;

  if (customer.latitude != null && customer.longitude != null) {
    return '${customer.latitude!.toStringAsFixed(5)}, '
        '${customer.longitude!.toStringAsFixed(5)}';
  }

  final company = customer.companyName.trim();
  if (company.isNotEmpty) return company;

  return 'No address on file';
}

/// Shows a modal prompt offering to capture GPS for a customer that is missing it.
/// On successful capture: updates local + attempts immediate Zoho update (via updateCustomerGps).
/// Returns the enriched Customer (with lat/lng) or null if user skipped / failed.
Future<Customer?> _showGpsCapturePrompt(
  BuildContext context,
  GpsCaptureBloc gpsBloc,
  Customer customer,
  bool isDark,
) {
  return showDialog<Customer>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => BlocProvider.value(
      value: gpsBloc,
      child: BlocListener<GpsCaptureBloc, GpsCaptureState>(
        listenWhen: (prev, curr) =>
            curr is GpsCaptureSuccess ||
            curr is GpsCapturePermissionDenied ||
            curr is GpsCaptureServiceDisabled ||
            curr is GpsCaptureFailure,
        listener: (ctx, state) {
          if (state is GpsCaptureSuccess) {
            Navigator.of(dialogCtx).pop(state.enrichedCustomer);
          } else if (state is GpsCapturePermissionDenied) {
            showSuccessSnackBar(context, 'Location permission denied.');
          } else if (state is GpsCaptureServiceDisabled) {
            showSuccessSnackBar(context, 'Enable location services to capture GPS.');
          } else if (state is GpsCaptureFailure) {
            showErrorSnackBar(context, 'Capture failed: ${state.message}');
          }
        },
        child: BlocBuilder<GpsCaptureBloc, GpsCaptureState>(
          builder: (ctx, state) {
            final capturing = state is GpsCaptureInProgress;
            return AlertDialog(
              title: const Text('Add GPS Location?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${customer.name} (${customer.companyName})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This customer has no GPS location yet. Capture the current device location now to enrich the record and push it to Zoho Books.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(null), // skip
                  child: const Text('SKIP'),
                ),
                FilledButton.icon(
                  onPressed: capturing
                      ? null
                      : () => ctx.read<GpsCaptureBloc>().add(
                            GpsCaptureRequested(
                              customer: customer,
                              persist: true,
                            ),
                          ),
                  icon: capturing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.gps_fixed),
                  label: const Text('CAPTURE GPS'),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
