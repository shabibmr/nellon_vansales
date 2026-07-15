import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/features/route/cubit/route_selection_ui_cubit.dart';
import 'package:van_sales/ui/features/route/cubit/route_selection_ui_state.dart';

void main() {
  late RouteSelectionUiCubit cubit;

  setUp(() {
    cubit = RouteSelectionUiCubit();
  });

  tearDown(() {
    cubit.close();
  });

  test('Initial state has no selected route', () {
    expect(cubit.state.selectedRouteId, isNull);
  });

  test('selectRoute updates selectedRouteId', () {
    cubit.selectRoute('route-abc');
    expect(cubit.state.selectedRouteId, 'route-abc');
  });

  test('selectRoute can be changed to a different route', () {
    cubit.selectRoute('route-1');
    cubit.selectRoute('route-2');
    expect(cubit.state.selectedRouteId, 'route-2');
  });

  test('clearSelection sets selectedRouteId to null', () {
    cubit.selectRoute('route-abc');
    cubit.clearSelection();
    expect(cubit.state.selectedRouteId, isNull);
  });

  test('RouteSelectionUiState equality works via Equatable', () {
    const a = RouteSelectionUiState(selectedRouteId: 'x');
    const b = RouteSelectionUiState(selectedRouteId: 'x');
    expect(a, equals(b));
  });

  test('States with different selectedRouteId are not equal', () {
    const a = RouteSelectionUiState(selectedRouteId: 'x');
    const b = RouteSelectionUiState(selectedRouteId: 'y');
    expect(a, isNot(equals(b)));
  });
}
