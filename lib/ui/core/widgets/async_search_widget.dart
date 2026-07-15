import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../core/extensions/org_context_extension.dart';
import 'empty_state.dart';
import '../../../domain/models/customer.dart';
import '../../../domain/models/item.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../../../data/services/injection.dart';
import '../bloc/async_search_bloc.dart';
import '../bloc/async_search_event.dart';
import '../bloc/async_search_state.dart';

/// Reusable widget that facilitates debounced in-memory search over local cache.
///
/// Implements a performant, debounced text search field that lets users search
/// for either [Customer]s or [Item]s within local cached directories.
class AsyncSearchWidget extends StatelessWidget {
  /// Callback triggered when a customer contact is selected from search results.
  final Function(Customer)? onCustomerSelected;

  /// Callback triggered when an inventory product is selected from search results.
  final Function(Item)? onItemSelected;

  /// Creates a new [AsyncSearchWidget].
  const AsyncSearchWidget({
    super.key,
    this.onCustomerSelected,
    this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AsyncSearchBloc(salesRepository: sl<SalesRepository>()),
      child: _AsyncSearchView(
        onCustomerSelected: onCustomerSelected,
        onItemSelected: onItemSelected,
      ),
    );
  }
}

class _AsyncSearchView extends StatefulWidget {
  final Function(Customer)? onCustomerSelected;
  final Function(Item)? onItemSelected;

  const _AsyncSearchView({
    this.onCustomerSelected,
    this.onItemSelected,
  });

  @override
  State<_AsyncSearchView> createState() => _AsyncSearchViewState();
}

class _AsyncSearchViewState extends State<_AsyncSearchView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<AsyncSearchBloc>().add(SearchQueryChanged(query));
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<AsyncSearchBloc>().add(const SearchCleared());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocBuilder<AsyncSearchBloc, AsyncSearchState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: SegmentedButton<SearchType>(
                segments: const [
                  ButtonSegment<SearchType>(
                    value: SearchType.customers,
                    label: Text('Clients'),
                    icon: Icon(Icons.people_outline_rounded),
                  ),
                  ButtonSegment<SearchType>(
                    value: SearchType.items,
                    label: Text('Inventory'),
                    icon: Icon(Icons.inventory_2_outlined),
                  ),
                ],
                selected: {state.searchType},
                onSelectionChanged: (Set<SearchType> newSelection) {
                  _searchController.clear();
                  context.read<AsyncSearchBloc>().add(
                        SearchTypeChanged(newSelection.first),
                      );
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppTheme.primaryIndigo.withValues(
                    alpha: 0.15,
                  ),
                  selectedForegroundColor: AppTheme.primaryIndigo,
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: state.searchType == SearchType.customers
                    ? 'Search active client names, shops...'
                    : 'Search catalog SKU, product names...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppTheme.primaryIndigo,
                ),
                suffixIcon: state.query.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.cancel,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                          size: 20,
                        ),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildResultsSection(context, state, isDark)),
          ],
        );
      },
    );
  }

  Widget _buildResultsSection(
    BuildContext context,
    AsyncSearchState state,
    bool isDark,
  ) {
    final cs = context.org.currencySymbol;

    if (state.status == AsyncSearchStatus.loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryIndigo),
            const SizedBox(height: 12),
            Text(
              'Searching database records...',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (!state.hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.searchType == SearchType.customers
                  ? Icons.people_outline_rounded
                  : Icons.inventory_2_outlined,
              size: 48,
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 12),
            Text(
              'Type to find ${state.searchType.name}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (state.searchType == SearchType.customers) {
      if (state.status == AsyncSearchStatus.empty) {
        return _buildEmptyState('No matching customers found.');
      }
      return ListView.separated(
        itemCount: state.customerResults.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final customer = state.customerResults[index];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.12),
                child: Text(
                  customer.sequence.toString(),
                  style: const TextStyle(
                    color: AppTheme.primaryIndigo,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                customer.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _customerAddressOrLocation(customer),
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Outstanding', style: TextStyle(fontSize: 10)),
                  Text(
                    '$cs${customer.outstandingBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: customer.outstandingBalance > 0
                          ? AppTheme.errorRose
                          : AppTheme.successEmerald,
                    ),
                  ),
                ],
              ),
              onTap: widget.onCustomerSelected != null
                  ? () => widget.onCustomerSelected!(customer)
                  : null,
            ),
          );
        },
      );
    } else {
      if (state.status == AsyncSearchStatus.empty) {
        return _buildEmptyState('No matching catalog items found.');
      }
      return ListView.separated(
        itemCount: state.itemResults.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = state.itemResults[index];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: CircleAvatar(
                backgroundColor: AppTheme.infoSky.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: AppTheme.infoSky,
                ),
              ),
              title: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'SKU: ${item.sku}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Stock: ${item.stock}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: item.stock > 0
                          ? AppTheme.successEmerald
                          : AppTheme.errorRose,
                    ),
                  ),
                  Text(
                    '$cs${item.rate.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryIndigo,
                    ),
                  ),
                ],
              ),
              onTap: widget.onItemSelected != null
                  ? () => widget.onItemSelected!(item)
                  : null,
            ),
          );
        },
      );
    }
  }

  Widget _buildEmptyState(String message) {
    return EmptyState(icon: Icons.info_outline, title: message);
  }
}

/// Prefer street address; fall back to GPS coordinates, then company name.
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