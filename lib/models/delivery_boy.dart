import 'package:cloud_firestore/cloud_firestore.dart';

class DeliveryBoy {
  final String id;
  final String name;
  final String email;
  final String phone;
  final List<String> assignedAreas;
  final bool isActive;
  final double latitude;
  final double longitude;
  final String? profileImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double commissionPerDelivery; // Add commission per delivery
  final double bonusPerDelivery; // Optional bonus per delivery

  DeliveryBoy({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.assignedAreas,
    required this.isActive,
    required this.latitude,
    required this.longitude,
    this.profileImageUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.commissionPerDelivery,
    this.bonusPerDelivery = 0.0,
  });

  factory DeliveryBoy.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeliveryBoy(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      assignedAreas: List<String>.from(data['assignedAreas'] ?? []),
      isActive: data['isActive'] ?? true,
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      profileImageUrl: data['profileImageUrl'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      commissionPerDelivery: (data['commissionPerDelivery'] ?? 50.0).toDouble(), // Default ₹50 per delivery
      bonusPerDelivery: (data['bonusPerDelivery'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'assignedAreas': assignedAreas,
      'isActive': isActive,
      'latitude': latitude,
      'longitude': longitude,
      'profileImageUrl': profileImageUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'commissionPerDelivery': commissionPerDelivery,
      'bonusPerDelivery': bonusPerDelivery,
    };
  }

  // Calculate total earnings for given number of deliveries
  double calculateEarnings(int deliveredCount) {
    return (deliveredCount * commissionPerDelivery) + (deliveredCount * bonusPerDelivery);
  }

  // Get formatted commission info
  String get commissionInfo {
    if (bonusPerDelivery > 0) {
      return '₹${commissionPerDelivery.toStringAsFixed(0)} + ₹${bonusPerDelivery.toStringAsFixed(0)} bonus per delivery';
    }
    return '₹${commissionPerDelivery.toStringAsFixed(0)} per delivery';
  }
}
