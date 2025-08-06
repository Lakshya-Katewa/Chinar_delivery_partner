import 'package:cloud_firestore/cloud_firestore.dart';
import 'address.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final String email;
  final DetailedAddress address;
  final String areaCode;
  final double walletBalance;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String referralCode;
  final String? referredBy;
  final bool hasUsedReferral;
  final bool referralRewardClaimed;
  final int successfulReferrals;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.areaCode,
    required this.walletBalance,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.referralCode,
    this.referredBy,
    required this.hasUsedReferral,
    required this.referralRewardClaimed,
    required this.successfulReferrals,
  });

  factory Customer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Customer(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      address: DetailedAddress.fromMap(data['address'] ?? {}),
      areaCode: data['areaCode'] ?? '',
      walletBalance: (data['walletBalance'] ?? 0.0).toDouble(),
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      referralCode: data['referralCode'] ?? '',
      referredBy: data['referredBy'],
      hasUsedReferral: data['hasUsedReferral'] ?? false,
      referralRewardClaimed: data['referralRewardClaimed'] ?? false,
      successfulReferrals: data['successfulReferrals'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'address': address.toMap(),
      'areaCode': areaCode,
      'walletBalance': walletBalance,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'referralCode': referralCode,
      'referredBy': referredBy,
      'hasUsedReferral': hasUsedReferral,
      'referralRewardClaimed': referralRewardClaimed,
      'successfulReferrals': successfulReferrals,
    };
  }
}
