import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/delivery_provider.dart';
import '../providers/delivery_auth_provider.dart';

class DeliveryRouteScreen extends StatefulWidget {
  const DeliveryRouteScreen({super.key});

  @override
  State<DeliveryRouteScreen> createState() => _DeliveryRouteScreenState();
}

class _DeliveryRouteScreenState extends State<DeliveryRouteScreen> {
  
  Future<void> _refreshRoute() async {
    final authProvider = Provider.of<DeliveryAuthProvider>(context, listen: false);
    final deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);
    
    if (authProvider.deliveryBoy != null) {
      await deliveryProvider.refreshLocationAndDistances(authProvider.deliveryBoy!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Route optimized from your current location'),
            backgroundColor: Colors.green,
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
        title: const Text('Optimized Delivery Route'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _refreshRoute,
            tooltip: 'Refresh route from current location',
          ),
        ],
      ),
      body: Consumer<DeliveryProvider>(
        builder: (context, deliveryProvider, child) {
          final deliveries = deliveryProvider.todayDeliveries;
          final currentLocation = deliveryProvider.currentLocation;
          
          if (deliveries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.route_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No deliveries for today',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your optimized route will appear here',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Current Location Info
              if (currentLocation != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.my_location, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Location',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            Text(
                              'Lat: ${currentLocation.latitude.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Lng: ${currentLocation.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Route optimized',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

              // Route Summary
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '${deliveries.length}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                        const Text('Stops', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${deliveries.fold(0.0, (sum, d) => sum + d.distanceFromBase).toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const Text('Total Distance', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '₹${deliveries.fold(0.0, (sum, d) => sum + d.totalAmount).toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                          ),
                        ),
                        const Text('Total Value', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Deliveries List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: deliveries.length,
                  itemBuilder: (context, index) {
                    final delivery = deliveries[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.green.shade700, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          delivery.customerName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              delivery.deliveryAddress.fullAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.navigation,
                                  size: 16,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${delivery.distanceFromBase.toStringAsFixed(1)} km away',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: delivery.status == 'delivered' 
                                        ? Colors.green.shade100 
                                        : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    delivery.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: delivery.status == 'delivered' 
                                          ? Colors.green.shade700 
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.navigation,
                            color: Colors.green.shade700,
                          ),
                          onPressed: () {
                            // TODO: Open maps navigation
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Navigate to ${delivery.customerName}'),
                              ),
                            );
                          },
                        ),
                        onTap: () {
                          // Show delivery details
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(delivery.customerName),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Phone: ${delivery.customerPhone}'),
                                  const SizedBox(height: 8),
                                  Text('Address: ${delivery.deliveryAddress.fullAddress}'),
                                  const SizedBox(height: 8),
                                  Text('Distance: ${delivery.distanceFromBase.toStringAsFixed(1)} km'),
                                  const SizedBox(height: 8),
                                  Text('Amount: ₹${delivery.totalAmount.toStringAsFixed(2)}'),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _refreshRoute,
        backgroundColor: Colors.green.shade700,
        icon: const Icon(Icons.my_location, color: Colors.white),
        label: const Text(
          'Update Route',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
