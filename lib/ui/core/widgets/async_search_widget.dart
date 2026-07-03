import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../core/extensions/org_context_extension.dart';
import 'empty_state.dart';
import '../../../domain/models/customer.dart';
import '../../../domain/models/item.dart';
import '../../../domain/repositories/sales_repository.dart';

/// Reusable stateful widget that facilitates asynchronous search queries.
///
/// Implements a performant, debounced text search field that lets users search
/// for either [Customer]s or [Item]s within local cached directories.
class AsyncSearchWidget extends StatefulWidget {
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
  State<AsyncSearchWidget> createState() => _AsyncSearchWidgetState();
}

/// Enumerates the search category modes.
enum SearchType { 
  /// Query customers list.
  customers, 
  /// Query van inventory list.
  items 
}

class _AsyncSearchWidgetState extends State<AsyncSearchWidget> {
  final _searchController = TextEditingController();
  SearchType _activeSearchType = SearchType.customers;
  Timer? _debounceTimer;
  
  bool _isLoading = false;
  List<Customer> _customerResults = [];
  List<Item> _itemResults = [];
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Triggers a debounced search function whenever the text changes.
  ///
  /// Delays search execution by 400ms after the user stops typing to prevent
  /// continuous database/cache search operations.
  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    
    if (query.trim().isEmpty) {
      setState(() {
        _customerResults = [];
        _itemResults = [];
        _isLoading = false;
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _executeAsyncSearch(query.trim());
    });
  }

  /// Queries the local [SalesRepository] for customer or inventory records matching the search term.
  ///
  /// Normalizes queries to lowercase and performs substring matching on key properties (name, sku, company, phone).
  Future<void> _executeAsyncSearch(String query) async {
    final salesRepo = context.read<SalesRepository>();
    final lowercaseQuery = query.toLowerCase();

    // Simulating realistic database index search / network latency
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    if (_activeSearchType == SearchType.customers) {
      final allCustomers = salesRepo.getCustomers();
      final filtered = allCustomers.where((cust) {
        return cust.name.toLowerCase().contains(lowercaseQuery) ||
            cust.companyName.toLowerCase().contains(lowercaseQuery) ||
            cust.phone.contains(query);
      }).toList();

      setState(() {
        _customerResults = filtered;
        _isLoading = false;
      });
    } else {
      final allItems = salesRepo.getItems();
      final filtered = allItems.where((item) {
        return item.name.toLowerCase().contains(lowercaseQuery) ||
            item.sku.toLowerCase().contains(lowercaseQuery);
      }).toList();

      setState(() {
        _itemResults = filtered;
        _isLoading = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Sleek Material 3 Segmented Toggle
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
            selected: {_activeSearchType},
            onSelectionChanged: (Set<SearchType> newSelection) {
              setState(() {
                _activeSearchType = newSelection.first;
                _clearSearch();
              });
            },
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.15),
              selectedForegroundColor: AppTheme.primaryIndigo,
              side: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. Interactive Search Box with clear button and loader
        TextFormField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: _activeSearchType == SearchType.customers
                ? 'Search active client names, shops...'
                : 'Search catalog SKU, product names...',
            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryIndigo),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.cancel,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      size: 20,
                    ),
                    onPressed: _clearSearch,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),

        // 3. Asynchronous List View Results
        Expanded(
          child: _buildResultsSection(isDark),
        ),
      ],
    );
  }

  Widget _buildResultsSection(bool isDark) {
    final cs = context.org.currencySymbol;
    if (_isLoading) {
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
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            )
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _activeSearchType == SearchType.customers
                  ? Icons.people_outline_rounded
                  : Icons.inventory_2_outlined,
              size: 48,
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 12),
            Text(
              'Type to find ${_activeSearchType.name}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            )
          ],
        ),
      );
    }

    if (_activeSearchType == SearchType.customers) {
      if (_customerResults.isEmpty) {
        return _buildEmptyState('No matching customers found.');
      }
      return ListView.separated(
        itemCount: _customerResults.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final customer = _customerResults[index];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.12),
                child: Text(
                  customer.sequence.toString(),
                  style: const TextStyle(color: AppTheme.primaryIndigo, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(customer.companyName, style: const TextStyle(fontSize: 12)),
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
                      color: customer.outstandingBalance > 0 ? AppTheme.errorRose : AppTheme.successEmerald,
                    ),
                  )
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
      if (_itemResults.isEmpty) {
        return _buildEmptyState('No matching catalog items found.');
      }
      return ListView.separated(
        itemCount: _itemResults.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _itemResults[index];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: AppTheme.infoSky.withValues(alpha: 0.12),
                child: const Icon(Icons.shopping_bag_outlined, color: AppTheme.infoSky),
              ),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 12)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Stock: ${item.stock}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: item.stock > 0 ? AppTheme.successEmerald : AppTheme.errorRose,
                    ),
                  ),
                  Text(
                    '$cs${item.rate.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryIndigo),
                  )
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
