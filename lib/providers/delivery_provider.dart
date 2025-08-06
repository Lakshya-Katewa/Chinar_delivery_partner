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
      // Check and request location permissions
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
        // Open app settings for user to manually enable
        await openAppSettings();
        return null;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }

      // Get current position with high accuracy
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      _currentLocation = position;
      debugPrint('Current location: ${position.latitude}, ${position.longitude}');
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
      // Get current location first
      final currentPosition = await _getCurrentLocation();
      
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      List<DeliveryOrder> deliveries = [];

      // Use current location if available, otherwise fall back to stored location
      final baseLatitude = currentPosition?.latitude ?? deliveryBoy.latitude;
      final baseLongitude = currentPosition?.longitude ?? deliveryBoy.longitude;

      debugPrint('Using base location: $baseLatitude, $baseLongitude');

      // Load regular orders - FIXED: Remove area code filtering for now
      try {
        final ordersQuery = await _firestore
            .collection('orders')
            .where('deliveryDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('deliveryDate', isLessThan: Timestamp.fromDate(endOfDay))
            .get();

        debugPrint('Found ${ordersQuery.docs.length} orders for today');

        for (var doc in ordersQuery.docs) {
          try {
            final orderData = doc.data();
            final deliveryAddress = orderData['deliveryAddress'] as Map<String, dynamic>?;
            
            if (deliveryAddress != null) {
              final destLat = _parseCoordinate(deliveryAddress['latitude']);
              final destLng = _parseCoordinate(deliveryAddress['longitude']);
              
              debugPrint('📍 Order ${doc.id} coordinates: $destLat, $destLng');
              debugPrint('   Raw data: lat=${deliveryAddress['latitude']}, lng=${deliveryAddress['longitude']}');

              // Validate destination coordinates
              if (destLat == 0.0 && destLng == 0.0) {
                debugPrint('⚠️  WARNING: Order ${doc.id} has invalid coordinates (0,0)');
                debugPrint('Address: ${deliveryAddress['fullAddress']}');
                debugPrint('Raw address data: $deliveryAddress');
                // Skip this order or use a default location
                continue;
              }

              final distance = await _calculateDistance(
                baseLatitude,
                baseLongitude,
                destLat,
                destLng,
              );

              // For now, load all orders regardless of area code
              // TODO: Implement proper area code filtering by getting customer data
              deliveries.add(DeliveryOrder.fromOrder(orderData, doc.id, distance));
              debugPrint('✅ Added order ${doc.id} with distance ${distance.toStringAsFixed(2)} km');
              debugPrint('   Destination: $destLat, $destLng');
            }
          } catch (e) {
            debugPrint('Error processing order ${doc.id}: $e');
          }
        }
      } catch (e) {
        debugPrint('Error loading orders: $e');
      }

      // Load subscription deliveries - FIXED: Get customer data for area code
      try {
        final subscriptionsQuery = await _firestore
            .collection('subscriptions')
            .where('status', isEqualTo: 'active')
            .get();

        debugPrint('Found ${subscriptionsQuery.docs.length} active subscriptions');

        for (var doc in subscriptionsQuery.docs) {
          try {
            final subData = doc.data();
            
            if (_shouldDeliverToday(subData)) {
              final customerId = subData['customerId'];
              final customerDoc = await _firestore.collection('customers').doc(customerId).get();
              
              if (customerDoc.exists) {
                final customerData = customerDoc.data()!;
                final customerAreaCode = customerData['areaCode'] ?? '';
                
                // Check if subscription is in assigned areas
                if (deliveryBoy.assignedAreas.contains(customerAreaCode) || deliveryBoy.assignedAreas.isEmpty) {
                  final address = customerData['address'] as Map<String, dynamic>?;
                  
                  if (address != null) {
                    final destLat = _parseCoordinate(address['latitude']);
                    final destLng = _parseCoordinate(address['longitude']);
                    
                    debugPrint('📍 Subscription ${doc.id} coordinates: $destLat, $destLng');
                    debugPrint('   Raw data: lat=${address['latitude']}, lng=${address['longitude']}');

                    // Validate destination coordinates
                    if (destLat == 0.0 && destLng == 0.0) {
                      debugPrint('⚠️  WARNING: Customer ${customerId} has invalid coordinates (0,0)');
                      debugPrint('Address: ${address['fullAddress']}');
                      // Skip this subscription or use a default location
                      continue;
                    }

                    final distance = await _calculateDistance(
                      baseLatitude,
                      baseLongitude,
                      destLat,
                      destLng,
                    );

                    // Pass the customer address to fromSubscription
                    deliveries.add(DeliveryOrder.fromSubscription(subData, doc.id, distance, address));
                    debugPrint('✅ Added subscription ${doc.id} with distance ${distance.toStringAsFixed(2)} km');
                    debugPrint('   Destination: $destLat, $destLng');
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

      // Sort by distance for optimized route
      deliveries.sort((a, b) => a.distanceFromBase.compareTo(b.distanceFromBase));
      debugPrint('Total deliveries loaded: ${deliveries.length}');

      // Debug: Print all delivery coordinates
      for (var delivery in deliveries) {
        debugPrint('Delivery to ${delivery.customerName}: ${delivery.deliveryAddress.latitude}, ${delivery.deliveryAddress.longitude}');
      }

      _todayDeliveries = deliveries;
      await _calculateStats(deliveryBoy);
    } catch (e) {
      _error = 'Failed to load deliveries: ${e.toString()}';
      debugPrint('Error loading deliveries: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add this method to get fresh current location
  Future<Position?> getCurrentLocationFresh() async {
    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions permanently denied');
        return null;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services disabled');
        return null;
      }

      // Get fresh position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      _currentLocation = position;
      debugPrint('Fresh location obtained: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      debugPrint('Error getting fresh location: $e');
      return null;
    }
  }

  // Update the refreshLocationAndDistances method
  Future<void> refreshLocationAndDistances(DeliveryBoy deliveryBoy) async {
    if (_todayDeliveries.isEmpty) return;

    try {
      // Always get fresh current location
      final currentPosition = await getCurrentLocationFresh();
      if (currentPosition == null) {
        debugPrint('Could not get fresh location for route refresh');
        return;
      }

      final baseLatitude = currentPosition.latitude;
      final baseLongitude = currentPosition.longitude;

      debugPrint('Refreshing route from fresh location: $baseLatitude, $baseLongitude');

      // Recalculate distances for all deliveries
      List<DeliveryOrder> updatedDeliveries = [];
      for (var delivery in _todayDeliveries) {
        // Validate delivery coordinates before calculating distance
        final destLat = delivery.deliveryAddress.latitude;
        final destLng = delivery.deliveryAddress.longitude;

        if (destLat == 0.0 && destLng == 0.0) {
          debugPrint('⚠️  Skipping delivery to ${delivery.customerName} - invalid coordinates');
          continue;
        }

        final newDistance = await _calculateDistance(
          baseLatitude,
          baseLongitude,
          destLat,
          destLng,
        );

        // Create updated delivery with new distance
        updatedDeliveries.add(DeliveryOrder(
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
        ));
      }

      // Sort by distance for optimized route
      updatedDeliveries.sort((a, b) => a.distanceFromBase.compareTo(b.distanceFromBase));

      _todayDeliveries = updatedDeliveries;
      debugPrint('Route refreshed with ${updatedDeliveries.length} deliveries from fresh location');
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing location and distances: $e');
    }
  }

  bool _shouldDeliverToday(Map<String, dynamic> subscriptionData) {
    final type = subscriptionData['type'] as String?;
    final startDate = (subscriptionData['startDate'] as Timestamp?)?.toDate();
    
    if (startDate == null) return false;
    
    final today = DateTime.now();
    final daysDifference = today.difference(startDate).inDays;
    
    switch (type) {
      case 'monthly':
      case 'weekly':
        return true; // Daily delivery
      case 'alternateDay':
        return daysDifference % 2 == 0; // Every alternate day
      default:
        return false;
    }
  }

  Future<double> _calculateDistance(double lat1, double lon1, double lat2, double lon2) async {
    try {
      if (lat1 == 0.0 && lon1 == 0.0) {
        debugPrint('Invalid base location: 0.0, 0.0');
        return 999.0; // Invalid base location
      }
      
      if (lat2 == 0.0 && lon2 == 0.0) {
        debugPrint('Invalid destination location: 0.0, 0.0');
        return 999.0; // Invalid destination
      }

      final distance = Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000; // Convert to km
      debugPrint('Distance calculated: ${distance.toStringAsFixed(2)} km from ($lat1, $lon1) to ($lat2, $lon2)');
      return distance;
    } catch (e) {
      debugPrint('Error calculating distance: $e');
      return 999.0; // Return high value for error cases
    }
  }

  Future<void> _calculateStats(DeliveryBoy deliveryBoy) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final startOfMonth = DateTime(today.year, today.month, 1);

      // Today's stats from loaded deliveries
      final todayDelivered = _todayDeliveries.where((d) => d.status == 'delivered').length;
      final todayPending = _todayDeliveries.where((d) => d.status != 'delivered').length;

      // Calculate earnings based on delivery count and commission rate
      final todayEarnings = deliveryBoy.calculateEarnings(todayDelivered);

      // Monthly stats with fallback
      int monthlyDelivered = 0;
      double monthlyEarnings = 0.0;

      try {
        // Try to get monthly delivered orders count
        final monthlyOrdersQuery = await _firestore
            .collection('orders')
            .where('deliveryDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
            .where('status', isEqualTo: 'delivered')
            .limit(100) // Add limit to reduce query complexity
            .get();

        monthlyDelivered = monthlyOrdersQuery.docs.length;

        // Try to get monthly delivered subscriptions count
        final monthlySubsQuery = await _firestore
            .collection('subscriptions')
            .where('status', isEqualTo: 'delivered')
            .where('updatedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
            .limit(100)
            .get();

        monthlyDelivered += monthlySubsQuery.docs.length;

        // Calculate monthly earnings based on total delivered count
        monthlyEarnings = deliveryBoy.calculateEarnings(monthlyDelivered);
      } catch (e) {
        debugPrint('Could not load monthly stats (missing index): $e');
        // Use today's stats as fallback
        monthlyDelivered = todayDelivered;
        monthlyEarnings = todayEarnings;
      }

      _stats = DeliveryStats(
        todayDelivered: todayDelivered,
        todayPending: todayPending,
        todayEarnings: todayEarnings,
        monthlyDelivered: monthlyDelivered,
        monthlyEarnings: monthlyEarnings,
        totalDistance: _todayDeliveries.fold(0.0, (sum, d) => sum + d.distanceFromBase),
        commissionPerDelivery: deliveryBoy.commissionPerDelivery,
        bonusPerDelivery: deliveryBoy.bonusPerDelivery,
      );

      debugPrint('Stats calculated: ${todayDelivered} delivered, ${todayPending} pending');
      debugPrint('Today earnings: ₹${todayEarnings.toStringAsFixed(2)} (${todayDelivered} × ₹${deliveryBoy.commissionPerDelivery})');
    } catch (e) {
      debugPrint('Error calculating stats: $e');
      // Create default stats if everything fails
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

  Future<void> updateOrderStatus(String orderId, String status, DeliveryType type) async {
    try {
      final collection = type == DeliveryType.order ? 'orders' : 'subscriptions';
      await _firestore.collection(collection).doc(orderId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local state
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

  Future<void> addMoneyToCustomerWallet({
    required String customerId,
    required double amount,
    required String deliveryBoyId,
    required String description,
  }) async {
    try {
      final batch = _firestore.batch();

      // Update customer wallet balance
      final customerRef = _firestore.collection('customers').doc(customerId);
      batch.update(customerRef, {
        'walletBalance': FieldValue.increment(amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create transaction record
      final transactionRef = _firestore.collection('transactions').doc();
      batch.set(transactionRef, {
        'customerId': customerId,
        'amount': amount,
        'type': 'credit',
        'description': description,
        'deliveryBoyId': deliveryBoyId,
        'paymentMethod': 'cash',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to add money to wallet: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  double _parseCoordinate(dynamic value) {
    if (value == null) {
      debugPrint('⚠️  Coordinate is null');
      return 0.0;
    }
    
    if (value is double) {
      debugPrint('✅ Coordinate is double: $value');
      return value;
    }
    
    if (value is int) {
      debugPrint('✅ Coordinate is int: $value, converting to double');
      return value.toDouble();
    }
    
    if (value is String) {
      final parsed = double.tryParse(value);
      debugPrint('✅ Coordinate is string: "$value", parsed to: $parsed');
      return parsed ?? 0.0;
    }
    
    debugPrint('⚠️  Unknown coordinate type: ${value.runtimeType}, value: $value');
    return 0.0;
  }
}
