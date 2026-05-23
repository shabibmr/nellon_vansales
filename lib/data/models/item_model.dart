import '../../domain/models/item.dart';

class ItemModel extends Item {
  const ItemModel({
    required super.id,
    required super.name,
    required super.sku,
    required super.rate,
    required super.stock,
    required super.description,
    required super.taxName,
    required super.taxPercentage,
  });

  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      id: json['item_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      sku: json['sku'] ?? '',
      rate: (json['rate'] ?? json['price'] ?? 0.0).toDouble(),
      stock: ((json['stock_on_hand'] ?? json['stock'] ?? 0) as num).toInt(),
      description: json['description'] ?? '',
      taxName: json['tax_name'] ?? json['taxName'] ?? 'GST 5%',
      taxPercentage: (json['tax_percentage'] ?? json['taxPercentage'] ?? 5.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'item_id': id,
      'name': name,
      'sku': sku,
      'rate': rate,
      'stock': stock,
      'stock_on_hand': stock,
      'description': description,
      'tax_name': taxName,
      'tax_percentage': taxPercentage,
    };
  }

  factory ItemModel.fromDomain(Item item) {
    return ItemModel(
      id: item.id,
      name: item.name,
      sku: item.sku,
      rate: item.rate,
      stock: item.stock,
      description: item.description,
      taxName: item.taxName,
      taxPercentage: item.taxPercentage,
    );
  }
}
