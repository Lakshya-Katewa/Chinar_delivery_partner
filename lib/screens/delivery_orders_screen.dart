import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/delivery_provider.dart';
import '../providers/delivery_auth_provider.dart';
import '../models/delivery_order.dart';
import 'package:geolocator/geolocator.dart';
import '../services/navigation_service.dart';
import 'package:flutter/foundation.dart';

class DeliveryOrdersScreen extends StatefulWidget {
  const DeliveryOrdersScreen({super.key});

  @override
  State<DeliveryOrdersScreen> createState() => _DeliveryOrdersScreenState();
}

class _DeliveryOrdersScreenState extends State<DeliveryOrdersScreen> {
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrders();
    });
  }

  Future<void> _loadOrders() async {
    final authProvider = Provider.of<DeliveryAuthProvider>(
      context,
      listen: false,
    );
    final deliveryProvider = Provider.of<DeliveryProvider>(
      context,
      listen: false,
    );

    if (authProvider.deliveryBoy != null) {
      await deliveryProvider.loadTodayDeliveries(authProvider.deliveryBoy!);
    }
  }

  Future<void> _refreshLocationAndRoute() async {
    final authProvider = Provider.of<DeliveryAuthProvider>(
      context,
      listen: false,
    );
    final deliveryProvider = Provider.of<DeliveryProvider>(
      context,
      listen: false,
    );

    if (authProvider.deliveryBoy != null) {
      await deliveryProvider.refreshLocationAndDistances(
        authProvider.deliveryBoy!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Route updated based on current location'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  List<DeliveryOrder> _getFilteredOrders(List<DeliveryOrder> orders) {
    switch (_selectedFilter) {
      case 'pending':
        return orders.where((o) => o.status != 'delivered').toList();
      case 'delivered':
        return orders.where((o) => o.status == 'delivered').toList();
      default:
        return orders;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'preparing':
        return Colors.purple;
      case 'out for delivery':
      case 'outfordelivery':
        return Colors.indigo;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Future<void> _openMaps(
    double latitude,
    double longitude,
    String address,
    String customerName,
  ) async {
    Position? currentLocation;

    try {
      currentLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Could not get current location for navigation: $e');
    }

    await NavigationService.showNavigationOptions(
      context: context,
      destinationLat: latitude,
      destinationLng: longitude,
      destinationName: customerName,
      currentLocation: currentLocation,
    );
  }

  void _showOrderActions(DeliveryOrder order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              order.customerName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Order #${order.id.substring(0, 8)}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),

            _buildActionButton(
              icon: Icons.phone,
              label: 'Call Customer',
              color: Colors.green,
              onTap: () {
                Navigator.pop(context);
                _makePhoneCall(order.customerPhone);
              },
            ),
            const SizedBox(height: 12),

            _buildActionButton(
              icon: Icons.navigation,
              label: 'Get Directions',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                _openMaps(
                  order.deliveryAddress.latitude,
                  order.deliveryAddress.longitude,
                  order.deliveryAddress.fullAddress,
                  order.customerName,
                );
              },
            ),
            const SizedBox(height: 12),

            if (order.status != 'delivered') ...[
              _buildActionButton(
                icon: Icons.local_shipping,
                label: 'Mark as Out for Delivery',
                color: Colors.orange,
                onTap: () => _updateOrderStatus(order, 'outForDelivery'),
              ),
              const SizedBox(height: 12),

              _buildActionButton(
                icon: Icons.check_circle,
                label: 'Mark as Delivered',
                color: Colors.green,
                onTap: () => _updateOrderStatus(order, 'delivered'),
              ),
              const SizedBox(height: 12),
            ],

            _buildActionButton(
              icon: Icons.close,
              label: 'Close',
              color: Colors.grey,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  // --- REQUIREMENT 2: 100 METER GPS VERIFICATION ---
  Future<void> _updateOrderStatus(DeliveryOrder order, String status) async {
    Navigator.pop(context); // Close bottom sheet

    // If the partner is marking as delivered, intercept and check GPS
    if (status == 'delivered') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );

        double distanceInMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          order.deliveryAddress.latitude,
          order.deliveryAddress.longitude,
        );

        Navigator.pop(context); // Dismiss loading

        // CHECK IF > 100 METERS
        if (distanceInMeters > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cannot mark as delivered! You are ${(distanceInMeters).toStringAsFixed(0)} meters away from the customer. You must be within 100 meters.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          return; // Abort the delivery mark
        }
      } catch (e) {
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to get GPS location: $e. Make sure location is turned on.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return; // Abort
      }
    }

    // Proceed with update if it wasn't 'delivered', or if the GPS check passed
    try {
      final deliveryProvider = Provider.of<DeliveryProvider>(
        context,
        listen: false,
      );
      await deliveryProvider.updateOrderStatus(order.id, status, order.type);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order status updated to ${status.replaceAll('_', ' ')}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Today\'s Deliveries'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _refreshLocationAndRoute,
            tooltip: 'Update route from current location',
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadOrders),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            color: Colors.white,
            child: Row(
              children: [
                Expanded(child: _buildFilterTab('all', 'All')),
                Expanded(child: _buildFilterTab('pending', 'Pending')),
                Expanded(child: _buildFilterTab('delivered', 'Delivered')),
              ],
            ),
          ),

          // Orders List
          Expanded(
            child: Consumer<DeliveryProvider>(
              builder: (context, deliveryProvider, child) {
                if (deliveryProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (deliveryProvider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading orders',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.red.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          deliveryProvider.error!,
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadOrders,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final filteredOrders = _getFilteredOrders(
                  deliveryProvider.todayDeliveries,
                );

                if (filteredOrders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No orders found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedFilter == 'all'
                              ? 'No deliveries scheduled for today'
                              : 'No $_selectedFilter orders',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadOrders,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredOrders.length,
                    itemBuilder: (context, index) {
                      final order = filteredOrders[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => _showOrderActions(order),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            order.customerName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            '${order.type.name.toUpperCase()} #${order.id.substring(0, 8)}',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(
                                          order.status,
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _getStatusColor(order.status),
                                        ),
                                      ),
                                      child: Text(
                                        order.status.toUpperCase(),
                                        style: TextStyle(
                                          color: _getStatusColor(order.status),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                ...order.items.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${item.quantity.toInt()} ${item.unit} ${item.productName}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '₹${item.totalPrice.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const Divider(),

                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        order.deliveryAddress.fullAddress,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${order.distanceFromBase.toStringAsFixed(1)} km',
                                      style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total: ₹${order.totalAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.phone,
                                            size: 20,
                                          ),
                                          onPressed: () => _makePhoneCall(
                                            order.customerPhone,
                                          ),
                                          color: Colors.green.shade700,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.navigation,
                                            size: 20,
                                          ),
                                          onPressed: () => _openMaps(
                                            order.deliveryAddress.latitude,
                                            order.deliveryAddress.longitude,
                                            order.deliveryAddress.fullAddress,
                                            order.customerName,
                                          ),
                                          color: Colors.blue.shade700,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String value, String label) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.green.shade700 : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.green.shade700 : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}
