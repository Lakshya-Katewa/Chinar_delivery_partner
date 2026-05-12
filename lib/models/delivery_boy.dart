import 'package:cloud_firestore/cloud_firestore.dart';

class DeliveryBoy {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String password;
  final List<String> assignedAreas;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double ratePerUnitQuantity;
  final double bonusPerUnitQuantity;
  final DateTime? lastPaymentDate;
  // Fields for location and UI
  final double latitude;
  final double longitude;
  final String profileImageUrl;

  DeliveryBoy({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.password,
    required this.assignedAreas,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.ratePerUnitQuantity = 0.0,
    this.bonusPerUnitQuantity = 0.0,
    this.lastPaymentDate,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.profileImageUrl = '',
  });

  // FIX for DeliveryDashboard: UI looks for commissionInfo
  String get commissionInfo =>
      "₹${ratePerUnitQuantity.toStringAsFixed(1)} / unit";

  // FIX for DeliveryProvider: Logic looks for commissionPerDelivery
  double get commissionPerDelivery => ratePerUnitQuantity;
  double get bonusPerDelivery => bonusPerUnitQuantity;

  // FIX for DeliveryProvider: Method for calculating earnings
  double calculateEarnings(int deliveredCount) {
    return deliveredCount * (ratePerUnitQuantity + bonusPerUnitQuantity);
  }

  factory DeliveryBoy.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return DeliveryBoy(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      password: data['password'] ?? '',
      assignedAreas: List<String>.from(data['assignedAreas'] ?? []),
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      ratePerUnitQuantity: (data['ratePerUnitQuantity'] ?? 0.0).toDouble(),
      bonusPerUnitQuantity: (data['bonusPerUnitQuantity'] ?? 0.0).toDouble(),
      lastPaymentDate: data['lastPaymentDate'] != null
          ? (data['lastPaymentDate'] as Timestamp).toDate()
          : null,
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      profileImageUrl: data['profileImageUrl'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'password': password,
      'assignedAreas': assignedAreas,
      'isActive': isActive,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
      'ratePerUnitQuantity': ratePerUnitQuantity,
      'bonusPerUnitQuantity': bonusPerUnitQuantity,
      'lastPaymentDate': lastPaymentDate != null
          ? Timestamp.fromDate(lastPaymentDate!)
          : null,
      'latitude': latitude,
      'longitude': longitude,
      'profileImageUrl': profileImageUrl,
    };
  }

  DeliveryBoy copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? password,
    List<String>? assignedAreas,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? ratePerUnitQuantity,
    double? bonusPerUnitQuantity,
    DateTime? lastPaymentDate,
    double? latitude,
    double? longitude,
    String? profileImageUrl,
  }) {
    return DeliveryBoy(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      password: password ?? this.password,
      assignedAreas: assignedAreas ?? this.assignedAreas,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ratePerUnitQuantity: ratePerUnitQuantity ?? this.ratePerUnitQuantity,
      bonusPerUnitQuantity: bonusPerUnitQuantity ?? this.bonusPerUnitQuantity,
      lastPaymentDate: lastPaymentDate ?? this.lastPaymentDate,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }
}
