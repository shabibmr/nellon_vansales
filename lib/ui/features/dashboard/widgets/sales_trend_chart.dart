import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../cubit/daily_stats_state.dart';

/// Line chart of the last 7 days' sales totals, styled to match [VanMetricCard].
class SalesTrendChart extends StatelessWidget {
  final List<DailySalesPoint> points;
  final bool isDark;
  final bool isGlass;
  final String currencySymbol;

  const SalesTrendChart({
    super.key,
    required this.points,
    required this.isDark,
    required this.isGlass,
    required this.currencySymbol,
  });

  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final titleColor = isGlass
        ? AppTheme.glassText
        : (isDark ? AppTheme.darkText : AppTheme.lightText);
    final labelColor = isGlass
        ? AppTheme.glassTextSecondary
        : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary);

    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 7 Days Sales',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: _buildChart(labelColor),
          ),
        ],
      ),
    );

    if (isGlass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.glassBorder, width: 1),
            ),
            child: content,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: content,
    );
  }

  Widget _buildChart(Color labelColor) {
    final maxValue = points.isEmpty
        ? 0.0
        : points.map((p) => p.total).reduce((a, b) => a > b ? a : b);
    final maxY = maxValue <= 0 ? 10.0 : maxValue * 1.2;

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].total),
    ];

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                final label = _weekdayLabels[points[index].date.weekday - 1];
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10, color: labelColor),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              return LineTooltipItem(
                '$currencySymbol${spot.y.toStringAsFixed(2)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primaryIndigo,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.primaryIndigo.withValues(alpha: 0.25),
                  AppTheme.primaryIndigo.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
