import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/route.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/repositories/sales_repository.dart';

// --- Events ---
abstract class RouteEvent extends Equatable {
  const RouteEvent();
  @override
  List<Object?> get props => [];
}

class LoadRoutes extends RouteEvent {}

class SelectActiveRoute extends RouteEvent {
  final String? routeId;
  const SelectActiveRoute(this.routeId);
  @override
  List<Object?> get props => [routeId];
}

class SearchCustomers extends RouteEvent {
  final String query;
  const SearchCustomers(this.query);
  @override
  List<Object?> get props => [query];
}

// --- States ---
class RouteState extends Equatable {
  final List<RouteModel> routes;
  final String? activeRouteId;
  final List<Customer> allCustomers; // All customers in active route
  final List<Customer> filteredCustomers; // Filtered/searched customers
  final bool isLoading;
  final String? errorMessage;

  const RouteState({
    this.routes = const [],
    this.activeRouteId,
    this.allCustomers = const [],
    this.filteredCustomers = const [],
    this.isLoading = false,
    this.errorMessage,
  });

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
class RouteBloc extends Bloc<RouteEvent, RouteState> {
  final SalesRepository _salesRepository;

  RouteBloc({
    required SalesRepository this._salesRepository,
  })  : super(const RouteState()) {
    on<LoadRoutes>(_onLoadRoutes);
    on<SelectActiveRoute>(_onSelectActiveRoute);
    on<SearchCustomers>(_onSearchCustomers);
  }

  Future<void> _onLoadRoutes(LoadRoutes event, Emitter<RouteState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final routes = _salesRepository.getRoutes();
      final activeRouteId = _salesRepository.activeRouteId;
      
      List<Customer> activeRouteCustomers = [];
      if (activeRouteId != null) {
        activeRouteCustomers = _salesRepository.getCustomers()
            .where((c) => c.routeId == activeRouteId)
            .toList();
        // Sort sequentially
        activeRouteCustomers.sort((a, b) => a.sequence.compareTo(b.sequence));
      }

      emit(state.copyWith(
        isLoading: false,
        routes: routes,
        activeRouteId: activeRouteId,
        allCustomers: activeRouteCustomers,
        filteredCustomers: activeRouteCustomers,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onSelectActiveRoute(SelectActiveRoute event, Emitter<RouteState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _salesRepository.setActiveRouteId(event.routeId);

      final activeRouteCustomers = _salesRepository.getCustomers()
          .where((c) => c.routeId == event.routeId)
          .toList();
      activeRouteCustomers.sort((a, b) => a.sequence.compareTo(b.sequence));

      emit(state.copyWith(
        isLoading: false,
        activeRouteId: event.routeId,
        allCustomers: activeRouteCustomers,
        filteredCustomers: activeRouteCustomers,
      ));
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
