import 'package:equatable/equatable.dart';

/// UI state for [RouteSelectionUiCubit].
class RouteSelectionUiState extends Equatable {
  /// The currently highlighted/selected route ID (before confirmation).
  final String? selectedRouteId;

  const RouteSelectionUiState({this.selectedRouteId});

  RouteSelectionUiState copyWith({String? selectedRouteId, bool clearSelection = false}) {
    return RouteSelectionUiState(
      selectedRouteId: clearSelection ? null : (selectedRouteId ?? this.selectedRouteId),
    );
  }

  @override
  List<Object?> get props => [selectedRouteId];
}
