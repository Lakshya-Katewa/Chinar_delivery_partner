import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/delivery_auth_provider.dart';
import '../providers/delivery_provider.dart';

class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() =>
      _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Use post-frame callback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocationAndData();
    });
  }

  Future<void> _initializeLocationAndData() async {
    await _requestLocationPermissions();
    await _initializeLocation();
    await _loadDeliveries();
  }

  Future<void> _requestLocationPermissions() async {
    try {
      // Request location permissions
      final status = await Permission.location.request();

      if (status.isDenied) {
        debugPrint('Location permission denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is required for accurate delivery routes',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else if (status.isPermanentlyDenied) {
        debugPrint('Location permission permanently denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please enable location permission in app settings',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error requesting location permissions: $e');
    }
  }

  Future<void> _initializeLocation() async {
    try {
      // Check permissions first
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission is required for navigation'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please enable location permission in app settings',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable location services for navigation'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Get current position with better error handling
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final authProvider = Provider.of<DeliveryAuthProvider>(
        context,
        listen: false,
      );
      await authProvider.updateLocation(position.latitude, position.longitude);

      debugPrint(
        'Location initialized successfully: ${position.latitude}, ${position.longitude}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not get current location: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _initializeLocation,
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadDeliveries() async {
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
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text('Getting current location...'),
                ), // Wrapped in Expanded
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }

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
              content: Text('Route updated from current location'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        // Dashboard - already here
        break;
      case 1:
        Navigator.pushNamed(context, '/delivery-orders');
        break;
      case 2:
        Navigator.pushNamed(context, '/delivery-customers');
        break;
      case 3:
        Navigator.pushNamed(context, '/delivery-profile');
        break;
    }

    // Reset to dashboard after navigation
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _selectedIndex = 0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        title: Consumer<DeliveryAuthProvider>(
          builder: (context, authProvider, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // Prevents vertical overflow
              children: [
                Text(
                  'Hello, ${authProvider.deliveryBoy?.name ?? 'Delivery Partner'}',
                  style: const TextStyle(fontSize: 16),
                  overflow:
                      TextOverflow.ellipsis, // Prevents horizontal overflow
                  maxLines: 1,
                ),
                Text(
                  authProvider.deliveryBoy?.commissionInfo ??
                      'Ready for deliveries',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  overflow:
                      TextOverflow.ellipsis, // Prevents horizontal overflow
                  maxLines: 1,
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () => Navigator.pushNamed(context, '/delivery-map'),
            tooltip: 'View Map',
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _refreshLocationAndRoute,
            tooltip: 'Update from current location',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDeliveries,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      const Text('Sign Out'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Are you sure you want to sign out?'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              color: Colors.orange.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You\'ll need to login again next time',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                final authProvider = Provider.of<DeliveryAuthProvider>(
                  context,
                  listen: false,
                );
                await authProvider.signOut();
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/delivery-login');
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDeliveries,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Commission Info Card
                Consumer<DeliveryAuthProvider>(
                  builder: (context, authProvider, child) {
                    final deliveryBoy = authProvider.deliveryBoy;
                    if (deliveryBoy == null) return const SizedBox.shrink();

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.currency_rupee,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Commission Rate',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                Text(
                                  deliveryBoy.commissionInfo,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Location Status Card
                Consumer<DeliveryProvider>(
                  builder: (context, deliveryProvider, child) {
                    final currentLocation = deliveryProvider.currentLocation;

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: currentLocation != null
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: currentLocation != null
                              ? Colors.green.shade200
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            currentLocation != null
                                ? Icons.location_on
                                : Icons.location_off,
                            color: currentLocation != null
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentLocation != null
                                      ? 'Location Active'
                                      : 'Location Unavailable',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: currentLocation != null
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                  ),
                                ),
                                Text(
                                  currentLocation != null
                                      ? 'Routes optimized from current location'
                                      : 'Using stored location for routes',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (currentLocation == null)
                            TextButton(
                              onPressed: _refreshLocationAndRoute,
                              child: const Text('Retry'),
                            ),
                        ],
                      ),
                    );
                  },
                ),

                // Stats Cards
                Consumer<DeliveryProvider>(
                  builder: (context, deliveryProvider, child) {
                    final stats = deliveryProvider.stats;

                    if (stats == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return Column(
                      children: [
                        // Today's Stats
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Delivered',
                                '${stats.todayDelivered}',
                                Icons.check_circle,
                                Colors.green,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                'Pending',
                                '${stats.todayPending}',
                                Icons.pending,
                                Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Today Earnings',
                                '₹${stats.todayEarnings.toStringAsFixed(0)}',
                                Icons.currency_rupee,
                                Colors.blue,
                                subtitle: stats.earningsBreakdown,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                'Potential',
                                '₹${stats.potentialTodayEarnings.toStringAsFixed(0)}',
                                Icons.trending_up,
                                Colors.purple,
                                subtitle: 'If all completed',
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Progress Card
                Consumer<DeliveryProvider>(
                  builder: (context, deliveryProvider, child) {
                    final stats = deliveryProvider.stats;
                    if (stats == null) return const SizedBox.shrink();

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Today\'s Progress',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${stats.todayCompletionRate.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: stats.todayCompletionRate / 100,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.green.shade700,
                              ),
                              minHeight: 8,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${stats.todayDelivered} of ${stats.todayTotal} deliveries completed',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                            if (stats.remainingEarnings > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Remaining earnings: ₹${stats.remainingEarnings.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: Colors.blue.shade600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Quick Actions
                const Text(
                  'Quick Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: _buildActionCard(
                        'View Orders',
                        Icons.list_alt,
                        Colors.blue,
                        () => Navigator.pushNamed(context, '/delivery-orders'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionCard(
                        'View Map',
                        Icons.map,
                        Colors.green,
                        () => Navigator.pushNamed(context, '/delivery-map'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionCard(
                        'Get Route',
                        Icons.navigation,
                        Colors.purple,
                        () => Navigator.pushNamed(context, '/delivery-route'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionCard(
                        'Customers',
                        Icons.people,
                        Colors.orange,
                        () =>
                            Navigator.pushNamed(context, '/delivery-customers'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Monthly Stats
                Consumer<DeliveryProvider>(
                  builder: (context, deliveryProvider, child) {
                    final stats = deliveryProvider.stats;
                    if (stats == null) return const SizedBox.shrink();

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'This Month',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${stats.monthlyDelivered}',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        'Deliveries',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: Colors.grey.shade300,
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '₹${stats.monthlyEarnings.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        'Earnings',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.green.shade700,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Customers'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          12,
        ), // Reduced padding slightly for smaller screens
        child: Column(
          children: [
            Icon(icon, color: color, size: 28), // Reduced icon size slightly
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown, // Shrinks the text if it gets too long
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Text(
              title,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
