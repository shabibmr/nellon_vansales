import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../domain/models/customer.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../../../data/models/sync_queue_item.dart';
import '../../../data/services/injection.dart';
import '../../../data/services/sync_worker.dart';
import '../../../data/services/zoho_api_client.dart';
import '../theme/app_theme.dart';
import '../extensions/org_context_extension.dart';
import '../utils/currency.dart';
import '../utils/snackbars.dart';

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
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => CustomerSelectorSheet(
        customers: customers,
        onSelected: onSelected,
        showCreateOption: showCreateOption,
        createOptionSubtitle: createOptionSubtitle,
        accentColor: accentColor,
        onCreateTap: onCreateTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    var allCustomers = List<Customer>.from(customers);
    final searchController = TextEditingController();
    var filtered = allCustomers;

    return StatefulBuilder(
      builder: (context, setModalState) {
        void onSearch(String query) {
          final q = query.toLowerCase();
          setModalState(() {
            filtered = q.isEmpty
                ? allCustomers
                : allCustomers.where((c) {
                    return c.name.toLowerCase().contains(q) ||
                        c.companyName.toLowerCase().contains(q) ||
                        c.phone.contains(q);
                  }).toList();
          });
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
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
                const SizedBox(height: 16),
                const Text(
                  'Select Customer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search by name, company or phone...',
                      prefixIcon: Icon(Icons.search, color: accentColor),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                if (showCreateOption) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_add_rounded,
                        color: accentColor,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Create New Customer',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    subtitle: Text(createOptionSubtitle),
                    onTap: () async {
                      Navigator.pop(context);
                      await onCreateTap?.call();
                    },
                  ),
                  const Divider(height: 1),
                ],
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No customers found',
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
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
                              subtitle: Text(customer.companyName),
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
                                Customer toSelect = customer;

                                // If GPS missing, prompt for immediate capture + Zoho update
                                if (customer.latitude == null || customer.longitude == null) {
                                  final enriched = await _showGpsCapturePrompt(
                                    context,
                                    customer,
                                    isDark,
                                  );
                                  if (enriched != null) {
                                    toSelect = enriched;
                                  }
                                  // If null returned or user skipped, still use original
                                }

                                onSelected(toSelect);
                                navigator.pop();
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Shows a modal prompt offering to capture GPS for a customer that is missing it.
/// On successful capture: updates local + attempts immediate Zoho update (via updateCustomerGps).
/// Returns the enriched Customer (with lat/lng) or null if user skipped / failed.
Future<Customer?> _showGpsCapturePrompt(
  BuildContext context,
  Customer customer,
  bool isDark,
) async {
  final repo = sl<SalesRepository>();
  double? capturedLat;
  double? capturedLng;
  bool capturing = false;

  return showDialog<Customer>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> doCapture() async {
          setState(() => capturing = true);

          try {
            var status = await Permission.locationWhenInUse.status;
            if (!status.isGranted) {
              status = await Permission.locationWhenInUse.request();
            }
            if (!status.isGranted) {
              if (ctx.mounted) {
                showSuccessSnackBar(ctx, 'Location permission denied.');
              }
              return;
            }

            if (!await Geolocator.isLocationServiceEnabled()) {
              if (ctx.mounted) {
                showSuccessSnackBar(ctx, 'Enable location services to capture GPS.');
              }
              return;
            }

            final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 12),
            );

            capturedLat = pos.latitude;
            capturedLng = pos.longitude;

            // 1. Update local cache immediately
            await repo.updateCustomerGps(customer.id, capturedLat!, capturedLng!);

            // 2. Immediate Zoho update (best effort). Falls back to queue below.
            bool remoteUpdated = false;
            if (customer.id.isNotEmpty && !customer.id.startsWith('temp_')) {
              try {
                final api = sl<ZohoApiClient>();
                await api.updateCustomerGps(customer.id, capturedLat!, capturedLng!);
                remoteUpdated = true;
              } catch (_) {}
            }

            // 3. Enqueue fallback + kick sync if remote didn't succeed right now
            if (!remoteUpdated) {
              final queueItem = SyncQueueItem(
                id: 'gps_${customer.id}_${DateTime.now().millisecondsSinceEpoch}',
                type: 'customer_gps_update',
                payload: {
                  'contact_id': customer.id,
                  'latitude': capturedLat,
                  'longitude': capturedLng,
                },
                status: SyncStatus.pending,
                timestamp: DateTime.now(),
              );
              await repo.enqueueSyncItem(queueItem);
              sl<SyncWorker>().syncPendingItems();
            }

            if (ctx.mounted) {
              Navigator.of(ctx).pop(
                customer.copyWith(latitude: capturedLat, longitude: capturedLng),
              );
            }
          } catch (e) {
            if (ctx.mounted) {
              showErrorSnackBar(ctx, 'Capture failed: $e');
            }
          } finally {
            if (ctx.mounted) setState(() => capturing = false);
          }
        }

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
              const SizedBox(height: 12),
              if (capturedLat != null)
                Text(
                  'Captured: ${capturedLat!.toStringAsFixed(6)}, ${capturedLng!.toStringAsFixed(6)}',
                  style: const TextStyle(color: AppTheme.successEmerald),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null), // skip
              child: const Text('SKIP'),
            ),
            FilledButton.icon(
              onPressed: capturing ? null : doCapture,
              icon: capturing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.gps_fixed),
              label: const Text('CAPTURE GPS'),
            ),
          ],
        );
      },
    ),
  );
}
