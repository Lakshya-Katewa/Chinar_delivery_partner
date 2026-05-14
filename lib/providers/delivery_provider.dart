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

      // CRITICAL FIX: Track which subscriptions already have a generated daily order
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

            // Log that this subscription has been handled for today
            if (orderData['subscriptionId'] != null) {
              processedSubIds.add(orderData['subscriptionId']);
            }

            bool isAreaMatched = false;
            final customerId = orderData['customerId'] as String?;

            if (customerId != null) {
              Map<String, dynamic>? customerData =
                  localCustomerCache[customerId];
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
                final customerAreaCode = customerData['areaCode'] ?? '';
                if (deliveryBoy.assignedAreas.contains(customerAreaCode))
                  isAreaMatched = true;
              }
            }

            if (!isAreaMatched) {
              final directAreaCode = orderData['areaCode'];
              if (directAreaCode != null &&
                  deliveryBoy.assignedAreas.contains(directAreaCode)) {
                isAreaMatched = true;
              } else {
                final deliveryAddress =
                    orderData['deliveryAddress'] as Map<String, dynamic>?;
                if (deliveryAddress != null) {
                  final addressAreaCode = deliveryAddress['areaCode'];
                  if (addressAreaCode != null &&
                      deliveryBoy.assignedAreas.contains(addressAreaCode))
                    isAreaMatched = true;
                }
              }
            }

            if (!isAreaMatched) continue;

            final deliveryAddress =
                orderData['deliveryAddress'] as Map<String, dynamic>?;
            if (deliveryAddress != null) {
              final destLat = _parseCoordinate(deliveryAddress['latitude']);
              final destLng = _parseCoordinate(deliveryAddress['longitude']);

              if (destLat == 0.0 && destLng == 0.0) continue;

              final distance = await _calculateDistance(
                baseLatitude,
                baseLongitude,
                destLat,
                destLng,
              );
              deliveries.add(
                DeliveryOrder.fromOrder(orderData, doc.id, distance),
              );
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
            // CRITICAL FIX: Skip if we already loaded today's receipt for this subscription
            if (processedSubIds.contains(doc.id)) continue;

            final subData = doc.data();

            if (_shouldDeliverToday(subData)) {
              bool isAreaMatched = false;
              Map<String, dynamic>? targetCustomerData;

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
                if (targetCustomerData != null) {
                  final customerAreaCode = targetCustomerData['areaCode'] ?? '';
                  if (deliveryBoy.assignedAreas.contains(customerAreaCode))
                    isAreaMatched = true;
                }
              }

              if (isAreaMatched && targetCustomerData != null) {
                final address =
                    targetCustomerData['address'] as Map<String, dynamic>?;
                if (address != null) {
                  final destLat = _parseCoordinate(address['latitude']);
                  final destLng = _parseCoordinate(address['longitude']);
                  if (destLat == 0.0 && destLng == 0.0) continue;

                  final distance = await _calculateDistance(
                    baseLatitude,
                    baseLongitude,
                    destLat,
                    destLng,
                  );
                  deliveries.add(
                    DeliveryOrder.fromSubscription(
                      subData,
                      doc.id,
                      distance,
                      address,
                    ),
                  );
                }
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
        if (destLat == 0.0 && destLng == 0.0) continue;

        final newDistance = await _calculateDistance(
          baseLatitude,
          baseLongitude,
          destLat,
          destLng,
        );
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
    final startDateRaw = (subscriptionData['startDate'] as Timestamp?)
        ?.toDate();
    if (startDateRaw == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = DateTime(
      startDateRaw.year,
      startDateRaw.month,
      startDateRaw.day,
    );

    if (today.isBefore(startDate)) return false;
    final daysDifference = today.difference(startDate).inDays;

    switch (type) {
      case 'monthly':
      case 'weekly':
      case 'trial':
        return true;
      case 'alternateDay':
        return daysDifference % 2 == 0;
      default:
        return false;
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
          // STRICTLY filter by the delivery boy so stats don't mix
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

  // CRITICAL FIX: Updated Order Status Function
  Future<void> updateOrderStatus(
    DeliveryOrder order,
    String status,
    DeliveryBoy deliveryBoy,
  ) async {
    try {
      String documentIdToUpdate = order.id;
      String collectionToUpdate = 'orders';

      // Check if this is a raw subscription being updated for the first time today
      bool isRawSubscriptionActedUpon =
          (order.type == DeliveryType.subscription && !order.id.contains('_'));

      Map<String, dynamic> updateData = {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isRawSubscriptionActedUpon) {
        // Create a unique daily order ID for this subscription delivery
        final now = DateTime.now();
        final todayStr = '${now.year}-${now.month}-${now.day}';
        documentIdToUpdate = '${order.id}_$todayStr';

        updateData['subscriptionId'] = order.id;
        updateData['customerId'] = order.customerId;
        updateData['type'] = 'subscription'; // Tells Admin app it's a sub
        updateData['deliveryDate'] = Timestamp.now();
        updateData['totalAmount'] = order.totalAmount;
      } else if (order.type == DeliveryType.subscription &&
          order.id.contains('_')) {
        // It's a daily subscription order that was already created
        collectionToUpdate = 'orders';
      } else {
        collectionToUpdate = 'orders'; // Standard one-time order
      }

      if (status == 'delivered' && deliveryBoy.id.isNotEmpty) {
        updateData['deliveredBy'] = deliveryBoy.id;

        // PUSH EARNINGS TO ADMIN DATABASE
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

      // Save to database
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

      // Update Local UI instantly
      final index = _todayDeliveries.indexWhere((d) => d.id == order.id);
      if (index != -1) {
        _todayDeliveries[index] = DeliveryOrder(
          id: documentIdToUpdate, // Swap to new Daily ID so future taps work
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
