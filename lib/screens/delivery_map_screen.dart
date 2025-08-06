import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/delivery_provider.dart';
import '../providers/delivery_auth_provider.dart';
import '../services/navigation_service.dart';
import '../models/delivery_order.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryMapScreen extends StatefulWidget {
  const DeliveryMapScreen({super.key});

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen> {
  final MapController _mapController = MapController();
  Position? _currentLocation;
  bool _isLoadingLocation = false;
  StreamSubscription<Position>? _locationSubscription;
  bool _isTrackingLocation = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Check permissions first
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied');
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() {
        _currentLocation = position;
      });

      // Update delivery provider with current location
      final deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);
      final authProvider = Provider.of<DeliveryAuthProvider>(context, listen: false);

      // Update location in auth provider
      await authProvider.updateLocation(position.latitude, position.longitude);

      // Center map on current location
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        15.0,
      );

      debugPrint('Current location updated: ${position.latitude}, ${position.longitude}');

      // Start real-time location tracking
      _startLocationTracking();

    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _getCurrentLocation,
            ),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  // Add real-time location tracking
  void _startLocationTracking() {
    if (_isTrackingLocation) return;

    _isTrackingLocation = true;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        setState(() {
          _currentLocation = position;
        });

        // Update auth provider with new location
        final authProvider = Provider.of<DeliveryAuthProvider>(context, listen: false);
        authProvider.updateLocation(position.latitude, position.longitude);

        debugPrint('Location updated: ${position.latitude}, ${position.longitude}');
      },
      onError: (error) {
        debugPrint('Location stream error: $error');
      },
    );
  }

  // Add dispose method to clean up location subscription
  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Map'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
          ),
        ],
      ),
      body: Consumer<DeliveryProvider>(
        builder: (context, deliveryProvider, child) {
          final deliveries = deliveryProvider.todayDeliveries;

          return Stack(
            children: [
              // Map
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation != null
                      ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
                      : const LatLng(34.0837, 74.7973), // Default to Srinagar
                  initialZoom: 13.0,
                  onTap: (tapPosition, point) {
                    // Handle map tap if needed
                  },
                ),
                children: [
                  // Map tiles (free OpenStreetMap)
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.chinar_delivery_boy_app',
                    maxZoom: 19,
                  ),

                  // Markers
                  MarkerLayer(
                    markers: [
                      // Current location marker
                      if (_currentLocation != null)
                        Marker(
                          point: LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),

                      // Delivery markers
                      ...deliveries.asMap().entries.map((entry) {
                        final index = entry.key;
                        final delivery = entry.value;

                        return Marker(
                          point: LatLng(
                            delivery.deliveryAddress.latitude,
                            delivery.deliveryAddress.longitude,
                          ),
                          width: 50,
                          height: 50,
                          child: GestureDetector(
                            onTap: () => _showDeliveryDetails(delivery, index + 1),
                            child: Container(
                              decoration: BoxDecoration(
                                color: delivery.status == 'delivered'
                                    ? Colors.green
                                    : Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),

                  // Route lines (simple straight lines for now)
                  if (_currentLocation != null && deliveries.isNotEmpty)
                    PolylineLayer(
                      polylines: deliveries.map((delivery) {
                        return Polyline(
                          points: [
                            LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                            LatLng(delivery.deliveryAddress.latitude, delivery.deliveryAddress.longitude),
                          ],
                          color: delivery.status == 'delivered'
                              ? Colors.green.withOpacity(0.6)
                              : Colors.red.withOpacity(0.6),
                          strokeWidth: 3.0,
                        );
                      }).toList(),
                    ),
                ],
              ),

              // Loading indicator
              if (_isLoadingLocation)
                Container(
                  color: Colors.black.withOpacity(0.3),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),

              // Delivery list overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: deliveries.length,
                          itemBuilder: (context, index) {
                            final delivery = deliveries[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: delivery.status == 'delivered'
                                      ? Colors.green
                                      : Colors.red,
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  delivery.customerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  '${delivery.distanceFromBase.toStringAsFixed(1)} km away',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.navigation),
                                  onPressed: () => _navigateToDelivery(delivery),
                                ),
                                onTap: () => _showDeliveryDetails(delivery, index + 1),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeliveryDetails(DeliveryOrder delivery, int orderNumber) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: delivery.status == 'delivered'
                      ? Colors.green
                      : Colors.red,
                  child: Text(
                    '$orderNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delivery.customerName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        delivery.customerPhone,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              'Address:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            Text(delivery.deliveryAddress.fullAddress),

            const SizedBox(height: 12),

            Row(
              children: [
                Text(
                  'Distance: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text('${delivery.distanceFromBase.toStringAsFixed(1)} km'),
                const Spacer(),
                Text(
                  'Amount: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  '₹${delivery.totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _navigateToDelivery(delivery);
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Navigate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _callCustomer(delivery.customerPhone);
                    },
                    icon: const Icon(Icons.phone),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToDelivery(DeliveryOrder delivery) async {
    // Get fresh current location before navigation
    Position? freshLocation;

    try {
      freshLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      debugPrint('Fresh location for navigation: ${freshLocation.latitude}, ${freshLocation.longitude}');
    } catch (e) {
      debugPrint('Could not get fresh location, using cached: $e');
      freshLocation = _currentLocation;
    }

    await NavigationService.showNavigationOptions(
      context: context,
      destinationLat: delivery.deliveryAddress.latitude,
      destinationLng: delivery.deliveryAddress.longitude,
      destinationName: delivery.customerName,
      currentLocation: freshLocation,
    );
  }

  Future<void> _callCustomer(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }
}
