import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/delivery_auth_provider.dart';
import '../providers/delivery_provider.dart';

class DeliveryProfileScreen extends StatefulWidget {
  const DeliveryProfileScreen({super.key});

  @override
  State<DeliveryProfileScreen> createState() => _DeliveryProfileScreenState();
}

class _DeliveryProfileScreenState extends State<DeliveryProfileScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Consumer<DeliveryAuthProvider>(
        builder: (context, authProvider, child) {
          final deliveryBoy = authProvider.deliveryBoy;
          
          if (deliveryBoy == null) {
            return const Center(child: Text('No profile data available'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Profile Header
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.green.shade100,
                          backgroundImage: deliveryBoy.profileImageUrl != null
                              ? NetworkImage(deliveryBoy.profileImageUrl!)
                              : null,
                          child: deliveryBoy.profileImageUrl == null
                              ? Text(
                                  deliveryBoy.name.isNotEmpty 
                                      ? deliveryBoy.name[0].toUpperCase()
                                      : 'D',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          deliveryBoy.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Delivery Partner',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: deliveryBoy.isActive 
                                ? Colors.green.shade100 
                                : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: deliveryBoy.isActive 
                                  ? Colors.green.shade700 
                                  : Colors.red.shade700,
                            ),
                          ),
                          child: Text(
                            deliveryBoy.isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              color: deliveryBoy.isActive 
                                  ? Colors.green.shade700 
                                  : Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Contact Information
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contact Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow(Icons.email, 'Email', deliveryBoy.email),
                        const SizedBox(height: 12),
                        _buildInfoRow(Icons.phone, 'Phone', deliveryBoy.phone),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Assigned Areas
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assigned Areas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (deliveryBoy.assignedAreas.isEmpty)
                          Text(
                            'No areas assigned',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: deliveryBoy.assignedAreas.map((area) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.blue.shade700),
                                ),
                                child: Text(
                                  area,
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Statistics
                Consumer<DeliveryProvider>(
                  builder: (context, deliveryProvider, child) {
                    final stats = deliveryProvider.stats;
                    
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Performance Stats',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (stats != null) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatItem(
                                      'Today Delivered',
                                      '${stats.todayDelivered}',
                                      Icons.check_circle,
                                      Colors.green,
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildStatItem(
                                      'Today Earnings',
                                      '₹${stats.todayEarnings.toStringAsFixed(0)}',
                                      Icons.currency_rupee,
                                      Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatItem(
                                      'Monthly Delivered',
                                      '${stats.monthlyDelivered}',
                                      Icons.local_shipping,
                                      Colors.orange,
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildStatItem(
                                      'Monthly Earnings',
                                      '₹${stats.monthlyEarnings.toStringAsFixed(0)}',
                                      Icons.account_balance_wallet,
                                      Colors.purple,
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              const Text(
                                'No statistics available',
                                style: TextStyle(color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Account Information
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Account Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          Icons.calendar_today,
                          'Joined',
                          '${deliveryBoy.createdAt.day}/${deliveryBoy.createdAt.month}/${deliveryBoy.createdAt.year}',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          Icons.update,
                          'Last Updated',
                          '${deliveryBoy.updatedAt.day}/${deliveryBoy.updatedAt.month}/${deliveryBoy.updatedAt.year}',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Sign Out Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Sign Out'),
                          content: const Text('Are you sure you want to sign out?'),
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
                        await authProvider.signOut();
                        if (mounted) {
                          Navigator.pushReplacementNamed(context, '/delivery-login');
                        }
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
