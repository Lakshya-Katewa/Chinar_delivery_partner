import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/address.dart';

enum DeliveryType { order, subscription }

class DeliveryOrder {
  final String id;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final DeliveryType type;
  final List<DeliveryItem> items;
  final double totalAmount;
  final DetailedAddress deliveryAddress;
  final DateTime deliveryDate;
  final String status;
  final String? notes;
  final String? paymentMethod;
  final double distanceFromBase;
  final DateTime createdAt;

  DeliveryOrder({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.type,
    required this.items,
    required this.totalAmount,
    required this.deliveryAddress,
    required this.deliveryDate,
    required this.status,
    this.notes,
    this.paymentMethod,
    required this.distanceFromBase,
    required this.createdAt,
  });

  factory DeliveryOrder.fromOrder(Map<String, dynamic> orderData, String orderId, double distance) {
    final items = (orderData['items'] as List<dynamic>?)
        ?.map((item) => DeliveryItem.fromMap(item as Map<String, dynamic>))
        .toList() ?? [];

    return DeliveryOrder(
      id: orderId,
      customerId: orderData['customerId'] ?? '',
      customerName: orderData['customerName'] ?? '',
      customerPhone: orderData['customerPhone'] ?? '',
      type: DeliveryType.order,
      items: items,
      totalAmount: (orderData['totalAmount'] ?? 0.0).toDouble(),
      deliveryAddress: DetailedAddress.fromMap(orderData['deliveryAddress'] as Map<String, dynamic>? ?? {}),
      deliveryDate: (orderData['deliveryDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: orderData['status'] ?? 'pending',
      notes: orderData['notes'],
      paymentMethod: orderData['paymentMethod'],
      distanceFromBase: distance,
      createdAt: (orderData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory DeliveryOrder.fromSubscription(
  Map<String, dynamic> subData, 
  String subId, 
  double distance,
  Map<String, dynamic> customerAddress, // Add customer address parameter
) {
  return DeliveryOrder(
    id: subId,
    customerId: subData['customerId'] ?? '',
    customerName: subData['customerName'] ?? '',
    customerPhone: subData['customerPhone'] ?? '',
    type: DeliveryType.subscription,
    items: [
      DeliveryItem(
        productName: subData['productName'] ?? '',
        quantity: (subData['quantity'] ?? 0.0).toDouble(),
        price: (subData['pricePerUnit'] ?? 0.0).toDouble(),
        unit: 'L', // Default unit for subscriptions
      )
    ],
    totalAmount: (subData['pricePerUnit'] ?? 0.0).toDouble() * (subData['quantity'] ?? 0.0).toDouble(),
    deliveryAddress: DetailedAddress.fromMap(customerAddress), // Use actual customer address
    deliveryDate: DateTime.now(),
    status: 'active',
    distanceFromBase: distance,
    createdAt: (subData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}
}

class DeliveryItem {
  final String productName;
  final double quantity;
  final double price;
  final String unit;

  DeliveryItem({
    required this.productName,
    required this.quantity,
    required this.price,
    required this.unit,
  });

  factory DeliveryItem.fromMap(Map<String, dynamic> map) {
    return DeliveryItem(
      productName: map['productName'] ?? '',
      quantity: (map['quantity'] ?? 0.0).toDouble(),
      price: (map['price'] ?? 0.0).toDouble(),
      unit: map['unit'] ?? '',
    );
  }

  double get totalPrice => quantity * price;
}
