import 'package:flutter/material.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/widgets/async_search_widget.dart';

/// Draggable search sheet that mounts the debounced [AsyncSearchWidget] for finding clients or inventory.
class GlobalSearchSheet extends StatelessWidget {
  /// Visual context.
  final bool isDark;

  /// Callback triggered when a customer record is tapped and selected.
  final ValueChanged<Customer> onCustomerSelected;

  /// Callback triggered when an inventory product item is tapped and selected.
  final ValueChanged<Item> onItemSelected;

  /// Creates a new [GlobalSearchSheet].
  const GlobalSearchSheet({
    super.key,
    required this.isDark,
    required this.onCustomerSelected,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Global Database Search',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AsyncSearchWidget(
                  onCustomerSelected: onCustomerSelected,
                  onItemSelected: onItemSelected,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
