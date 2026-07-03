import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/route.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/repositories/sales_repository.dart';

// --- Events ---

/// Base class for all route-related events processed by [RouteBloc].
abstract class RouteEvent extends Equatable {
  const RouteEvent();
  @override
  List<Object?> get props => [];
}

/// Fired to trigger loading all available route configurations from local database storage.
class LoadRoutes extends RouteEvent {}

/// Fired when an agent selects a specific route to activate for deliveries.
class SelectActiveRoute extends RouteEvent {
  /// The unique route ID being locked.
  final String? routeId;

  /// Creates a new [SelectActiveRoute] event.
  const SelectActiveRoute(this.routeId);
  @override
  List<Object?> get props => [routeId];
}

/// Fired to perform instant substring filtering of customers within the active route directory.
class SearchCustomers extends RouteEvent {
  /// User query string.
  final String query;

  /// Creates a new [SearchCustomers] event.
  const SearchCustomers(this.query);
  @override
  List<Object?> get props => [query];
}

// --- States ---

/// Holds structural state variables representing active routes, loaders, errors, and filtered customer directories.
class RouteState extends Equatable {
  /// List of all delivery routes stored in local cache.
  final List<RouteModel> routes;

  /// Unique identifier of the locked active route.
  final String? activeRouteId;

  /// Total collection of customer profiles assigned to the active route.
  final List<Customer> allCustomers; // All customers in active route

  /// Sorted, query-filtered subset of customer profiles.
  final List<Customer> filteredCustomers; // Filtered/searched customers

  /// State loading flags.
  final bool isLoading;

  /// Descriptive error trace message.
  final String? errorMessage;

  /// Creates a [RouteState].
  const RouteState({
    this.routes = const [],
    this.activeRouteId,
    this.allCustomers = const [],
    this.filteredCustomers = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  /// Returns a copy of [RouteState] with replaced values for specified fields.
  RouteState copyWith({
    List<RouteModel>? routes,
    String? activeRouteId,
    List<Customer>? allCustomers,
    List<Customer>? filteredCustomers,
    bool? isLoading,
    String? errorMessage,
  }) {
    return RouteState(
      routes: routes ?? this.routes,
      activeRouteId: activeRouteId ?? this.activeRouteId,
      allCustomers: allCustomers ?? this.allCustomers,
      filteredCustomers: filteredCustomers ?? this.filteredCustomers,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    routes,
    activeRouteId,
    allCustomers,
    filteredCustomers,
    isLoading,
    errorMessage,
  ];
}

// --- Bloc ---

/// Business Logic Component managing selected delivery routes and active customer sequences.
///
/// Gates route locking parameters, triggers sequential customer loading, and coordinates customer searching.
class RouteBloc extends Bloc<RouteEvent, RouteState> {
  final SalesRepository _salesRepository;

  /// Instantiates a new [RouteBloc] utilizing the provided sales repository.
  RouteBloc({required this._salesRepository}) : super(const RouteState()) {
    on<LoadRoutes>(_onLoadRoutes);
    on<SelectActiveRoute>(_onSelectActiveRoute);
    on<SearchCustomers>(_onSearchCustomers);
  }

  Future<void> _onLoadRoutes(LoadRoutes event, Emitter<RouteState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final routes = _salesRepository.getRoutes();
      final activeRouteId = _salesRepository.activeRouteId;

      final allCustomers = _salesRepository.getCustomers();
      allCustomers.sort((a, b) => a.name.compareTo(b.name));

      emit(
        state.copyWith(
          isLoading: false,
          routes: routes,
          activeRouteId: activeRouteId,
          allCustomers: allCustomers,
          filteredCustomers: allCustomers,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onSelectActiveRoute(
    SelectActiveRoute event,
    Emitter<RouteState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _salesRepository.setActiveRouteId(event.routeId);

      final allCustomers = _salesRepository.getCustomers();
      allCustomers.sort((a, b) => a.name.compareTo(b.name));

      emit(
        state.copyWith(
          isLoading: false,
          activeRouteId: event.routeId,
          allCustomers: allCustomers,
          filteredCustomers: allCustomers,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onSearchCustomers(SearchCustomers event, Emitter<RouteState> emit) {
    if (event.query.isEmpty) {
      emit(state.copyWith(filteredCustomers: state.allCustomers));
      return;
    }

    final query = event.query.toLowerCase();
    final filtered = state.allCustomers.where((cust) {
      return cust.name.toLowerCase().contains(query) ||
          cust.companyName.toLowerCase().contains(query) ||
          cust.phone.contains(query);
    }).toList();

    emit(state.copyWith(filteredCustomers: filtered));
  }
}
