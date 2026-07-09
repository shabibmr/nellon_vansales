import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'date_range_filter_card.dart';

/// A single tap-to-sort column header for [SortableReportScaffold].
class ReportColumn<F extends Enum> {
  final String label;
  final int flex;
  final F field;
  final bool alignEnd;

  const ReportColumn({
    required this.label,
    required this.flex,
    required this.field,
    this.alignEnd = true,
  });
}

/// A single aggregate stat shown in the summary strip above the list.
class ReportSummaryChip {
  final String label;
  final String value;
  final Color color;

  const ReportSummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });
}

/// Shared chrome for aggregation-style report pages: app bar with
/// refresh/loading indicator, optional date-range filter, optional summary
/// chip strip, a sortable column header, and a sorted/empty list body.
///
/// Each report page owns its own data fetching, aggregation, and sort
/// comparator (row shapes differ per report); this widget only renders the
/// shared frame around whatever rows and columns it's given.
class SortableReportScaffold<T, F extends Enum> extends StatelessWidget {
  final String title;
  final bool isLoading;
  final VoidCallback onRefresh;
  final List<T> rows;
  final List<ReportColumn<F>> columns;
  final F sortField;
  final bool sortAscending;
  final ValueChanged<F> onSort;
  final Widget Function(BuildContext context, T row) itemBuilder;
  final List<ReportSummaryChip> summaryChips;

  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback? onStartDateTap;
  final VoidCallback? onEndDateTap;
  final VoidCallback? onClearDate;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final String emptyFilteredMessage;

  const SortableReportScaffold({
    super.key,
    required this.title,
    required this.isLoading,
    required this.onRefresh,
    required this.rows,
    required this.columns,
    required this.sortField,
    required this.sortAscending,
    required this.onSort,
    required this.itemBuilder,
    this.summaryChips = const [],
    this.startDate,
    this.endDate,
    this.onStartDateTap,
    this.onEndDateTap,
    this.onClearDate,
    this.emptyIcon = Icons.bar_chart_rounded,
    this.emptyTitle = 'No data',
    this.emptyMessage = 'No records found.',
    this.emptyFilteredMessage = 'No records in the selected date range.',
  });

  bool get _hasDateFilter => onStartDateTap != null && onEndDateTap != null;

  Widget _sortIcon(F field) {
    if (sortField != field) {
      return const Icon(Icons.unfold_more, size: 14, color: Colors.grey);
    }
    return Icon(
      sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
      size: 14,
      color: AppTheme.primaryIndigo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActiveFilter = startDate != null || endDate != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh from Zoho',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: onRefresh,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_hasDateFilter)
              DateRangeFilterCard(
                startDate: startDate,
                endDate: endDate,
                onStartTap: onStartDateTap!,
                onEndTap: onEndDateTap!,
                onClear: onClearDate,
              ),
            if (summaryChips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    for (int i = 0; i < summaryChips.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _SummaryChipView(chip: summaryChips[i])),
                    ],
                  ],
                ),
              ),
            if (rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      for (final col in columns)
                        Expanded(
                          flex: col.flex,
                          child: GestureDetector(
                            onTap: () => onSort(col.field),
                            child: Row(
                              mainAxisAlignment: col.alignEnd
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: col.alignEnd
                                  ? [
                                      _sortIcon(col.field),
                                      const SizedBox(width: 2),
                                      Text(
                                        col.label,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ]
                                  : [
                                      Text(
                                        col.label,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      _sortIcon(col.field),
                                    ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            emptyIcon,
                            size: 64,
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            emptyTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hasActiveFilter
                                ? emptyFilteredMessage
                                : emptyMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF475569)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) =>
                          itemBuilder(context, rows[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChipView extends StatelessWidget {
  final ReportSummaryChip chip;

  const _SummaryChipView({required this.chip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: chip.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: chip.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chip.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: chip.color,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              chip.value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
