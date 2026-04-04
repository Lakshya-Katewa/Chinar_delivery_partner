import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
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
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        return null;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      _currentLocation = position;
      return position;
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  Future<void> loadTodayDeliveries(DeliveryBoy deliveryBoy) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final currentPosition = await _getCurrentLocation();

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      List<DeliveryOrder> deliveries = [];

      final baseLatitude = currentPosition?.latitude ?? deliveryBoy.latitude;
      final baseLongitude = currentPosition?.longitude ?? deliveryBoy.longitude;

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

      try {
        final subscriptionsQuery = await _firestore
            .collection('subscriptions')
            .where('status', isEqualTo: 'active')
            .get();

        for (var doc in subscriptionsQuery.docs) {
          try {
            final subData = doc.data();

            if (_shouldDeliverToday(subData)) {
              final customerId = subData['customerId'];
              final customerDoc = await _firestore
                  .collection('customers')
                  .doc(customerId)
                  .get();

              if (customerDoc.exists) {
                final customerData = customerDoc.data()!;
                final customerAreaCode = customerData['areaCode'] ?? '';

                if (deliveryBoy.assignedAreas.contains(customerAreaCode) ||
                    deliveryBoy.assignedAreas.isEmpty) {
                  final address =
                      customerData['address'] as Map<String, dynamic>?;

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

  Future<Position?> getCurrentLocationFresh() async {
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

  Future<void> refreshLocationAndDistances(DeliveryBoy deliveryBoy) async {
    if (_todayDeliveries.isEmpty) return;

    try {
      final currentPosition = await getCurrentLocationFresh();
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
      debugPrint('Error refreshing location and distances: $e');
    }
  }

  // --- REQUIREMENT 3: SUBSCRIPTION START DATE LOGIC ---
  bool _shouldDeliverToday(Map<String, dynamic> subscriptionData) {
    final type = subscriptionData['type'] as String?;
    final startDateRaw = (subscriptionData['startDate'] as Timestamp?)
        ?.toDate();

    if (startDateRaw == null) return false;

    final now = DateTime.now();
    // Normalize times to strictly check the dates
    final today = DateTime(now.year, now.month, now.day);
    final startDate = DateTime(
      startDateRaw.year,
      startDateRaw.month,
      startDateRaw.day,
    );

    // If the subscription starts in the future (e.g. tomorrow), do not show it today
    if (today.isBefore(startDate)) {
      return false;
    }

    final daysDifference = today.difference(startDate).inDays;

    switch (type) {
      case 'monthly':
      case 'weekly':
      case 'trial':
        return true; // Daily delivery
      case 'alternateDay':
        return daysDifference % 2 == 0; // Every alternate day
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
            .limit(100)
            .get();

        monthlyDelivered = monthlyOrdersQuery.docs.length;

        final monthlySubsQuery = await _firestore
            .collection('subscriptions')
            .where('status', isEqualTo: 'delivered')
            .where(
              'updatedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
            )
            .limit(100)
            .get();

        monthlyDelivered += monthlySubsQuery.docs.length;
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
    String orderId,
    String status,
    DeliveryType type,
  ) async {
    try {
      final collection = type == DeliveryType.order
          ? 'orders'
          : 'subscriptions';
      await _firestore.collection(collection).doc(orderId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final index = _todayDeliveries.indexWhere((d) => d.id == orderId);
      if (index != -1) {
        _todayDeliveries[index] = DeliveryOrder(
          id: _todayDeliveries[index].id,
          customerId: _todayDeliveries[index].customerId,
          customerName: _todayDeliveries[index].customerName,
          customerPhone: _todayDeliveries[index].customerPhone,
          type: _todayDeliveries[index].type,
          items: _todayDeliveries[index].items,
          totalAmount: _todayDeliveries[index].totalAmount,
          deliveryAddress: _todayDeliveries[index].deliveryAddress,
          deliveryDate: _todayDeliveries[index].deliveryDate,
          status: status,
          notes: _todayDeliveries[index].notes,
          paymentMethod: _todayDeliveries[index].paymentMethod,
          distanceFromBase: _todayDeliveries[index].distanceFromBase,
          createdAt: _todayDeliveries[index].createdAt,
        );
        notifyListeners();
      }
    } catch (e) {
      throw Exception('Failed to update order status: $e');
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
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed ?? 0.0;
    }
    return 0.0;
  }
}
