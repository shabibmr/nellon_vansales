import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/models/sales_invoice_model.dart';

// --- Events ---
abstract class SalesInvoiceEvent extends Equatable {
  const SalesInvoiceEvent();
  @override
  List<Object?> get props => [];
}

class AddToCart extends SalesInvoiceEvent {
  final Item item;
  final int quantity;
  const AddToCart(this.item, this.quantity);
  @override
  List<Object?> get props => [item, quantity];
}

class RemoveFromCart extends SalesInvoiceEvent {
  final Item item;
  const RemoveFromCart(this.item);
  @override
  List<Object?> get props => [item];
}

class UpdateCartQuantity extends SalesInvoiceEvent {
  final Item item;
  final int quantity;
  const UpdateCartQuantity(this.item, this.quantity);
  @override
  List<Object?> get props => [item, quantity];
}

class ClearCart extends SalesInvoiceEvent {}

class CheckoutRequested extends SalesInvoiceEvent {
  final Customer customer;
  final String notes;
  const CheckoutRequested({required this.customer, required this.notes});

  @override
  List<Object?> get props => [customer, notes];
}

// --- States ---
abstract class SalesInvoiceState extends Equatable {
  const SalesInvoiceState();
  @override
  List<Object?> get props => [];
}

class SalesInvoiceInitial extends SalesInvoiceState {
  final Map<Item, int> cart;
  const SalesInvoiceInitial({this.cart = const {}});
  @override
  List<Object?> get props => [cart];
}

class SalesInvoiceLoading extends SalesInvoiceState {}

class SalesInvoiceSuccess extends SalesInvoiceState {
  final SalesInvoice invoice;
  const SalesInvoiceSuccess(this.invoice);
  @override
  List<Object?> get props => [invoice];
}

class SalesInvoiceFailure extends SalesInvoiceState {
  final String errorMessage;
  const SalesInvoiceFailure(this.errorMessage);
  @override
  List<Object?> get props => [errorMessage];
}

// --- Bloc ---
class SalesInvoiceBloc extends Bloc<SalesInvoiceEvent, SalesInvoiceState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;
  Map<Item, int> _cart = {};

  SalesInvoiceBloc({
    required SalesRepository this._salesRepository,
    required SyncRepository this._syncRepository,
  })  : super(const SalesInvoiceInitial()) {
    on<AddToCart>(_onAddToCart);
    on<RemoveFromCart>(_onRemoveFromCart);
    on<UpdateCartQuantity>(_onUpdateCartQuantity);
    on<ClearCart>(_onClearCart);
    on<CheckoutRequested>(_onCheckoutRequested);
  }

  void _onAddToCart(AddToCart event, Emitter<SalesInvoiceState> emit) {
    final existingQty = _cart[event.item] ?? 0;
    
    // Check local stock limits
    if (existingQty + event.quantity > event.item.stock) {
      emit(const SalesInvoiceFailure('Cannot add item: Exceeds available van inventory stock'));
      emit(SalesInvoiceInitial(cart: Map.from(_cart)));
      return;
    }

    _cart = Map.from(_cart)..[event.item] = existingQty + event.quantity;
    emit(SalesInvoiceInitial(cart: _cart));
  }

  void _onRemoveFromCart(RemoveFromCart event, Emitter<SalesInvoiceState> emit) {
    _cart = Map.from(_cart)..remove(event.item);
    emit(SalesInvoiceInitial(cart: _cart));
  }

  void _onUpdateCartQuantity(UpdateCartQuantity event, Emitter<SalesInvoiceState> emit) {
    if (event.quantity <= 0) {
      _cart = Map.from(_cart)..remove(event.item);
    } else {
      if (event.quantity > event.item.stock) {
        emit(const SalesInvoiceFailure('Cannot adjust quantity: Exceeds available van inventory stock'));
        emit(SalesInvoiceInitial(cart: Map.from(_cart)));
        return;
      }
      _cart = Map.from(_cart)..[event.item] = event.quantity;
    }
    emit(SalesInvoiceInitial(cart: _cart));
  }

  void _onClearCart(ClearCart event, Emitter<SalesInvoiceState> emit) {
    _cart = {};
    emit(SalesInvoiceInitial(cart: _cart));
  }

  Future<void> _onCheckoutRequested(CheckoutRequested event, Emitter<SalesInvoiceState> emit) async {
    if (_cart.isEmpty) {
      emit(const SalesInvoiceFailure('Cart is empty'));
      return;
    }

    emit(SalesInvoiceLoading());
    try {
      final lineItems = _cart.entries.map((entry) {
        return InvoiceLineItem(
          item: entry.key,
          quantity: entry.value,
          rate: entry.key.rate,
          taxPercentage: entry.key.taxPercentage,
        );
      }).toList();

      final tempId = 'temp_inv_${DateTime.now().millisecondsSinceEpoch}';
      final invoice = SalesInvoice(
        id: tempId,
        invoiceNumber: 'INV-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        customerId: event.customer.id,
        customerName: event.customer.name,
        date: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 7)), // 7-day default term
        items: lineItems,
        notes: event.notes,
        isPendingSync: true,
      );

      // 1. Save to local History Box (handles stock deduction automatically in our service!)
      await _salesRepository.saveLocalInvoice(invoice);

      // 2. Enqueue offline Sync Pack
      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'invoice',
        payload: SalesInvoiceModel.fromDomain(invoice).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _salesRepository.enqueueSyncItem(syncItem);

      // 3. Clear active cart
      _cart = {};

      emit(SalesInvoiceSuccess(invoice));
      
      // 4. Fire network upload immediately (runs in background asynchronously)
      _syncRepository.triggerSync();
    } catch (e) {
      emit(SalesInvoiceFailure(e.toString()));
    }
  }
}
