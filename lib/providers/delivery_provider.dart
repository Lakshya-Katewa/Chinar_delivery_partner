import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/delivery_order.dart';
import '../models/delivery_stats.dart';
import '../models/delivery_boy.dart';

class DeliveryProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<DeliveryOrder> _todayDeliveries = [];
  DeliveryStats? _stats;
  bool _isLoading = false;
  String? _error;
  Position? _currentLocation;

  List<DeliveryOrder> get todayDeliveries => _todayDeliveries;
  DeliveryStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Position? get currentLocation => _currentLocation;

  Future<Position?> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      _currentLocation = position;
      return position;
    } catch (e) {
      return null;
    }
  }

  Future<void> loadTodayDeliveries(DeliveryBoy deliveryBoy) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (deliveryBoy.assignedAreas.isEmpty) {
        _todayDeliveries = [];
        await _calculateStats(deliveryBoy);
        _isLoading = false;
        notifyListeners();
        return;
      }

      final currentPosition = await _getCurrentLocation();

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      List<DeliveryOrder> deliveries = [];
      final baseLatitude = currentPosition?.latitude ?? deliveryBoy.latitude;
      final baseLongitude = currentPosition?.longitude ?? deliveryBoy.longitude;

      Map<String, Map<String, dynamic>> localCustomerCache = {};
      Set<String> processedSubIds = {};

      // 1. LOAD STANDARD ORDERS (AND DAILY SUBSCRIPTION RECEIPTS)
      try {
        final ordersQuery = await _firestore
            .collection('orders')
            .where(
              'deliveryDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where('deliveryDate', isLessThan: Timestamp.fromDate(endOfDay))
            .get();

        for (var doc in ordersQuery.docs) {
          try {
            final orderData = doc.data();

            if (orderData['subscriptionId'] != null) {
              processedSubIds.add(orderData['subscriptionId']);
            }

            bool isAreaMatched = false;
            final customerId = orderData['customerId'] as String?;
            Map<String, dynamic>? customerData;

            if (customerId != null) {
              customerData = localCustomerCache[customerId];
              if (customerData == null) {
                final cDoc = await _firestore
                    .collection('customers')
                    .doc(customerId)
                    .get();
                if (cDoc.exists) {
                  customerData = cDoc.data()!;
                  localCustomerCache[customerId] = customerData;
                }
              }
              if (customerData != null) {
                final customerAreaCode =
                    customerData['areaCode']?.toString() ??
                    customerData['pinCode']?.toString() ??
                    '';
                if (deliveryBoy.assignedAreas.contains(customerAreaCode)) {
                  isAreaMatched = true;
                }
              }
            }

            Map<String, dynamic>? deliveryAddress =
                orderData['deliveryAddress'] as Map<String, dynamic>?;

            // If the receipt doesn't have an address, grab it from the customer profile
            if (deliveryAddress == null && customerData != null) {
              deliveryAddress =
                  customerData['address'] as Map<String, dynamic>?;
              orderData['deliveryAddress'] = deliveryAddress;
            }

            if (!isAreaMatched) {
              final directAreaCode = orderData['areaCode']?.toString();
              if (directAreaCode != null &&
                  deliveryBoy.assignedAreas.contains(directAreaCode)) {
                isAreaMatched = true;
              } else if (deliveryAddress != null) {
                final addressAreaCode =
                    deliveryAddress['areaCode']?.toString() ??
                    deliveryAddress['pinCode']?.toString();
                if (addressAreaCode != null &&
                    deliveryBoy.assignedAreas.contains(addressAreaCode)) {
                  isAreaMatched = true;
                }
              }
            }

            if (!isAreaMatched) continue;

            if (deliveryAddress != null) {
              final destLat = _parseCoordinate(deliveryAddress['latitude']);
              final destLng = _parseCoordinate(deliveryAddress['longitude']);

              double distance = 999.0;
              if (destLat != 0.0 && destLng != 0.0) {
                distance = await _calculateDistance(
                  baseLatitude,
                  baseLongitude,
                  destLat,
                  destLng,
                );
              }

              deliveries.add(
                DeliveryOrder.fromOrder(orderData, doc.id, distance),
              );
            } else {
              deliveries.add(DeliveryOrder.fromOrder(orderData, doc.id, 999.0));
            }
          } catch (e) {
            debugPrint('Error processing order ${doc.id}: $e');
          }
        }
      } catch (e) {
        debugPrint('Error loading orders: $e');
      }

      // 2. LOAD ACTIVE SUBSCRIPTIONS
      try {
        final subscriptionsQuery = await _firestore
            .collection('subscriptions')
            .where('status', isEqualTo: 'active')
            .get();

        for (var doc in subscriptionsQuery.docs) {
          try {
            if (processedSubIds.contains(doc.id)) continue;

            final subData = doc.data();

            if (_shouldDeliverToday(subData)) {
              bool isAreaMatched = false;
              Map<String, dynamic>? targetCustomerData;

              // Step 1: Check the subscription document directly
              final subAreaCode = subData['areaCode']?.toString() ?? '';
              if (deliveryBoy.assignedAreas.contains(subAreaCode)) {
                isAreaMatched = true;
              }

              // Step 2: If the sub document doesn't match, check the customer profile
              final customerId = subData['customerId'] as String?;
              if (customerId != null) {
                targetCustomerData = localCustomerCache[customerId];
                if (targetCustomerData == null) {
                  final cDoc = await _firestore
                      .collection('customers')
                      .doc(customerId)
                      .get();
                  if (cDoc.exists) {
                    targetCustomerData = cDoc.data()!;
                    localCustomerCache[customerId] = targetCustomerData;
                  }
                }

                if (!isAreaMatched && targetCustomerData != null) {
                  final custAreaCode =
                      targetCustomerData['areaCode']?.toString() ?? '';
                  if (deliveryBoy.assignedAreas.contains(custAreaCode)) {
                    isAreaMatched = true;
                  }

                  // Also check the nested customer address pinCode (Critical for Admin App Match)
                  if (!isAreaMatched) {
                    final custAddress =
                        targetCustomerData['address'] as Map<String, dynamic>?;
                    final custPinCode =
                        custAddress?['pinCode']?.toString() ?? '';
                    if (deliveryBoy.assignedAreas.contains(custPinCode)) {
                      isAreaMatched = true;
                    }
                  }
                }
              }

              // Step 3: If any area matches, build the order
              if (isAreaMatched) {
                Map<String, dynamic>? address;

                // Prioritize customer address if available
                if (targetCustomerData != null &&
                    targetCustomerData['address'] != null) {
                  address =
                      targetCustomerData['address'] as Map<String, dynamic>;
                } else if (subData['address'] != null) {
                  // Fallback to basic address string if it exists in sub
                  address = {
                    'fullAddress': subData['address'].toString(),
                    'latitude': 0.0,
                    'longitude': 0.0,
                  };
                }

                double distance = 999.0;
                if (address != null) {
                  final destLat = _parseCoordinate(address['latitude']);
                  final destLng = _parseCoordinate(address['longitude']);

                  if (destLat != 0.0 && destLng != 0.0) {
                    distance = await _calculateDistance(
                      baseLatitude,
                      baseLongitude,
                      destLat,
                      destLng,
                    );
                  }
                }

                deliveries.add(
                  DeliveryOrder.fromSubscription(
                    subData,
                    doc.id,
                    distance,
                    address ?? {'fullAddress': 'No Address Provided'},
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Error processing subscription ${doc.id}: $e');
          }
        }
      } catch (e) {
        debugPrint('Error loading subscriptions: $e');
      }

      deliveries.sort(
        (a, b) => a.distanceFromBase.compareTo(b.distanceFromBase),
      );
      _todayDeliveries = deliveries;
      await _calculateStats(deliveryBoy);
    } catch (e) {
      _error = 'Failed to load deliveries: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshLocationAndDistances(DeliveryBoy deliveryBoy) async {
    if (_todayDeliveries.isEmpty) return;
    try {
      final currentPosition = await _getCurrentLocation();
      if (currentPosition == null) return;

      final baseLatitude = currentPosition.latitude;
      final baseLongitude = currentPosition.longitude;

      List<DeliveryOrder> updatedDeliveries = [];
      for (var delivery in _todayDeliveries) {
        final destLat = delivery.deliveryAddress.latitude;
        final destLng = delivery.deliveryAddress.longitude;

        double newDistance = delivery.distanceFromBase;
        if (destLat != 0.0 && destLng != 0.0) {
          newDistance = await _calculateDistance(
            baseLatitude,
            baseLongitude,
            destLat,
            destLng,
          );
        }

        updatedDeliveries.add(
          DeliveryOrder(
            id: delivery.id,
            customerId: delivery.customerId,
            customerName: delivery.customerName,
            customerPhone: delivery.customerPhone,
            type: delivery.type,
            items: delivery.items,
            totalAmount: delivery.totalAmount,
            deliveryAddress: delivery.deliveryAddress,
            deliveryDate: delivery.deliveryDate,
            status: delivery.status,
            notes: delivery.notes,
            paymentMethod: delivery.paymentMethod,
            distanceFromBase: newDistance,
            createdAt: delivery.createdAt,
          ),
        );
      }
      updatedDeliveries.sort(
        (a, b) => a.distanceFromBase.compareTo(b.distanceFromBase),
      );
      _todayDeliveries = updatedDeliveries;
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing distances: $e');
    }
  }

  bool _shouldDeliverToday(Map<String, dynamic> subscriptionData) {
    final type = subscriptionData['type'] as String?;

    DateTime? startDate;
    final rawDate = subscriptionData['startDate'];

    if (rawDate is Timestamp) {
      startDate = rawDate.toDate();
    } else if (rawDate is String) {
      startDate = DateTime.tryParse(rawDate);
    }

    if (startDate == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);

    if (today.isBefore(start)) return false;

    final daysDifference = today.difference(start).inDays;

    switch (type) {
      case 'monthly':
      case 'weekly':
      case 'trial':
      case 'daily':
        return true;
      case 'alternateDay':
        return daysDifference % 2 == 0;
      default:
        return true;
    }
  }

  Future<double> _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) async {
    try {
      if (lat1 == 0.0 && lon1 == 0.0) return 999.0;
      if (lat2 == 0.0 && lon2 == 0.0) return 999.0;
      return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
    } catch (e) {
      return 999.0;
    }
  }

  Future<void> _calculateStats(DeliveryBoy deliveryBoy) async {
    try {
      final today = DateTime.now();
      final startOfMonth = DateTime(today.year, today.month, 1);

      final todayDelivered = _todayDeliveries
          .where((d) => d.status == 'delivered')
          .length;
      final todayPending = _todayDeliveries
          .where((d) => d.status != 'delivered')
          .length;
      final todayEarnings = deliveryBoy.calculateEarnings(todayDelivered);

      int monthlyDelivered = 0;
      double monthlyEarnings = 0.0;

      try {
        final monthlyOrdersQuery = await _firestore
            .collection('orders')
            .where(
              'deliveryDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
            )
            .where('status', isEqualTo: 'delivered')
            .limit(1000)
            .get();

        monthlyDelivered += monthlyOrdersQuery.docs.where((doc) {
          final data = doc.data();
          return data['deliveredBy'] == deliveryBoy.id;
        }).length;

        monthlyEarnings = deliveryBoy.calculateEarnings(monthlyDelivered);
      } catch (e) {
        monthlyDelivered = todayDelivered;
        monthlyEarnings = todayEarnings;
      }

      _stats = DeliveryStats(
        todayDelivered: todayDelivered,
        todayPending: todayPending,
        todayEarnings: todayEarnings,
        monthlyDelivered: monthlyDelivered,
        monthlyEarnings: monthlyEarnings,
        totalDistance: _todayDeliveries.fold(
          0.0,
          (sum, d) => sum + d.distanceFromBase,
        ),
        commissionPerDelivery: deliveryBoy.commissionPerDelivery,
        bonusPerDelivery: deliveryBoy.bonusPerDelivery,
      );
    } catch (e) {
      _stats = DeliveryStats(
        todayDelivered: 0,
        todayPending: 0,
        todayEarnings: 0.0,
        monthlyDelivered: 0,
        monthlyEarnings: 0.0,
        totalDistance: 0.0,
        commissionPerDelivery: deliveryBoy.commissionPerDelivery,
        bonusPerDelivery: deliveryBoy.bonusPerDelivery,
      );
    }
  }

  Future<void> updateOrderStatus(
    DeliveryOrder order,
    String status,
    DeliveryBoy deliveryBoy,
  ) async {
    try {
      String documentIdToUpdate = order.id;
      String collectionToUpdate = 'orders';

      bool isRawSubscriptionActedUpon =
          (order.type == DeliveryType.subscription && !order.id.contains('_'));

      Map<String, dynamic> updateData = {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isRawSubscriptionActedUpon) {
        final now = DateTime.now();
        final todayStr = '${now.year}-${now.month}-${now.day}';
        documentIdToUpdate = '${order.id}_$todayStr';

        updateData['subscriptionId'] = order.id;
        updateData['customerId'] = order.customerId;
        updateData['type'] = 'subscription';
        updateData['deliveryDate'] = Timestamp.now();
        updateData['totalAmount'] = order.totalAmount;
      } else if (order.type == DeliveryType.subscription &&
          order.id.contains('_')) {
        collectionToUpdate = 'orders';
      } else {
        collectionToUpdate = 'orders';
      }

      if (status == 'delivered' && deliveryBoy.id.isNotEmpty) {
        updateData['deliveredBy'] = deliveryBoy.id;

        try {
          final double earned = deliveryBoy.calculateEarnings(1);
          await _firestore.collection('delivery_boys').doc(deliveryBoy.id).set({
            'unpaidEarnings': FieldValue.increment(earned),
            'walletBalance': FieldValue.increment(earned),
            'totalEarnings': FieldValue.increment(earned),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Earnings update error: $e');
        }
      }

      if (isRawSubscriptionActedUpon) {
        await _firestore
            .collection('orders')
            .doc(documentIdToUpdate)
            .set(updateData, SetOptions(merge: true));
      } else {
        await _firestore
            .collection(collectionToUpdate)
            .doc(documentIdToUpdate)
            .update(updateData);
      }

      final index = _todayDeliveries.indexWhere((d) => d.id == order.id);
      if (index != -1) {
        _todayDeliveries[index] = DeliveryOrder(
          id: documentIdToUpdate,
          customerId: order.customerId,
          customerName: order.customerName,
          customerPhone: order.customerPhone,
          type: order.type,
          items: order.items,
          totalAmount: order.totalAmount,
          deliveryAddress: order.deliveryAddress,
          deliveryDate: order.deliveryDate,
          status: status,
          notes: order.notes,
          paymentMethod: order.paymentMethod,
          distanceFromBase: order.distanceFromBase,
          createdAt: order.createdAt,
        );
      }

      await _calculateStats(deliveryBoy);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update status: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  double _parseCoordinate(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
