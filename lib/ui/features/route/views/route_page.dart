import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../bloc/route_bloc.dart';

/// The Route Selection View.
///
/// Prompts sales agents to choose and lock their active daily delivery route on app launch or route shift.
class RouteSelectionPage extends StatefulWidget {
  /// Creates a new [RouteSelectionPage].
  const RouteSelectionPage({super.key});

  @override
  State<RouteSelectionPage> createState() => _RouteSelectionPageState();
}

class _RouteSelectionPageState extends State<RouteSelectionPage> {
  String? _selectedRouteId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<RouteBloc>().add(LoadRoutes());
            },
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header description
              Text(
                'Select Active Route',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please select your assigned van route for today. This locks in the sequential customer database and active warehouse stock rules.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Active Route List Container
              Expanded(
                child: BlocBuilder<RouteBloc, RouteState>(
                  builder: (context, state) {
                    if (state.isLoading) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
                      );
                    }

                    if (state.routes.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map_outlined, size: 64, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                            const SizedBox(height: 16),
                            const Text('No routes found in local database cache.'),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () {
                                context.read<RouteBloc>().add(LoadRoutes());
                              },
                              child: const Text('RETRY LOADING'),
                            )
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: state.routes.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final route = state.routes[index];
                        final isSelected = _selectedRouteId == route.id;

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedRouteId = route.id;
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryIndigo.withValues(alpha: 0.08)
                                  : (isDark ? AppTheme.darkSurface : AppTheme.lightSurface),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryIndigo
                                    : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primaryIndigo.withValues(alpha: 0.15),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                // Route Icon wrapper
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primaryIndigo.withValues(alpha: 0.15)
                                        : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.alt_route,
                                    color: isSelected ? AppTheme.primaryIndigo : AppTheme.infoSky,
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // Route Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        route.name,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? AppTheme.darkText : AppTheme.lightText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        route.description,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Checkmark Indicator
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppTheme.successEmerald,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Bottom selection action button
              ElevatedButton(
                onPressed: _selectedRouteId == null
                    ? null
                    : () {
                        context.read<RouteBloc>().add(SelectActiveRoute(_selectedRouteId));
                      },
                child: const Text('CONFIRM ACTIVE ROUTE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
