import 'package:flutter_bloc/flutter_bloc.dart';
import 'route_selection_ui_state.dart';

/// Manages the ephemeral UI selection state for the Route Selection page.
///
/// Decouples which route card is highlighted from the actual [RouteBloc]
/// confirmation logic, so the page itself can be stateless.
class RouteSelectionUiCubit extends Cubit<RouteSelectionUiState> {
  RouteSelectionUiCubit() : super(const RouteSelectionUiState());

  /// Highlights the given [routeId] as the pending user selection.
  void selectRoute(String routeId) {
    emit(state.copyWith(selectedRouteId: routeId));
  }

  /// Clears the current selection (e.g. after route list reload).
  void clearSelection() {
    emit(state.copyWith(clearSelection: true));
  }
}
