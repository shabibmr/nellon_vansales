import 'package:equatable/equatable.dart';

class Item extends Equatable {
  final String id;
  final String name;
  final String sku;
  final double rate;
  final int stock;
  final String description;
  final String taxName;
  final double taxPercentage;

  const Item({
    required this.id,
    required this.name,
    required this.sku,
    required this.rate,
    required this.stock,
    required this.description,
    required this.taxName,
    required this.taxPercentage,
  });

  Item copyWith({
    String? id,
    String? name,
    String? sku,
    double? rate,
    int? stock,
    String? description,
    String? taxName,
    double? taxPercentage,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      rate: rate ?? this.rate,
      stock: stock ?? this.stock,
      description: description ?? this.description,
      taxName: taxName ?? this.taxName,
      taxPercentage: taxPercentage ?? this.taxPercentage,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        sku,
        rate,
        stock,
        description,
        taxName,
        taxPercentage,
      ];
}
