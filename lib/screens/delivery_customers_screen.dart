import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/delivery_auth_provider.dart';
import '../providers/delivery_provider.dart';
import '../models/customer.dart';

class DeliveryCustomersScreen extends StatefulWidget {
  const DeliveryCustomersScreen({super.key});

  @override
  State<DeliveryCustomersScreen> createState() => _DeliveryCustomersScreenState();
}

class _DeliveryCustomersScreenState extends State<DeliveryCustomersScreen> {
  List<Customer> _customers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<DeliveryAuthProvider>(context, listen: false);
      final deliveryBoy = authProvider.deliveryBoy;
      
      if (deliveryBoy == null) return;

      // Load customers from assigned areas
      final customersQuery = await FirebaseFirestore.instance
          .collection('customers')
          .where('areaCode', whereIn: deliveryBoy.assignedAreas.isNotEmpty 
              ? deliveryBoy.assignedAreas 
              : ['dummy']) // Prevent empty whereIn
          .get();

      setState(() {
        _customers = customersQuery.docs
            .map((doc) => Customer.fromFirestore(doc))
            .toList();
        _customers.sort((a, b) => a.name.compareTo(b.name));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading customers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Customer> get _filteredCustomers {
    if (_searchQuery.isEmpty) {
      return _customers;
    }
    return _customers.where((customer) =>
        customer.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        customer.phone.contains(_searchQuery) ||
        customer.email.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  void _showAddMoneyDialog(Customer customer) {
    showDialog(
      context: context,
      builder: (dialogContext) => _AddMoneyDialog(
        customer: customer,
        onMoneyAdded: (amount) {
          _updateCustomerBalance(customer, amount);
        },
      ),
    );
  }

  void _updateCustomerBalance(Customer customer, double amount) {
    // Update local customer data
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index != -1) {
      setState(() {
        _customers[index] = Customer(
          id: customer.id,
          name: customer.name,
          phone: customer.phone,
          email: customer.email,
          address: customer.address,
          areaCode: customer.areaCode,
          walletBalance: customer.walletBalance + amount,
          isActive: customer.isActive,
          createdAt: customer.createdAt,
          updatedAt: DateTime.now(),
          referralCode: customer.referralCode,
          referredBy: customer.referredBy,
          hasUsedReferral: customer.hasUsedReferral,
          referralRewardClaimed: customer.referralRewardClaimed,
          successfulReferrals: customer.successfulReferrals,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('My Customers'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustomers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customers...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Customers List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty 
                                  ? 'No customers found'
                                  : 'No customers in your area',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCustomers,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final customer = _filteredCustomers[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.shade100,
                                  child: Text(
                                    customer.name.isNotEmpty 
                                        ? customer.name[0].toUpperCase()
                                        : 'C',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  customer.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(customer.phone),
                                    Text(customer.areaCode),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.account_balance_wallet,
                                          size: 16,
                                          color: Colors.green.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '₹${customer.walletBalance.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: ElevatedButton.icon(
                                  onPressed: () => _showAddMoneyDialog(customer),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add Money'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// Separate dialog widget to handle TextEditingController properly
class _AddMoneyDialog extends StatefulWidget {
  final Customer customer;
  final Function(double) onMoneyAdded;

  const _AddMoneyDialog({
    required this.customer,
    required this.onMoneyAdded,
  });

  @override
  State<_AddMoneyDialog> createState() => _AddMoneyDialogState();
}

class _AddMoneyDialogState extends State<_AddMoneyDialog> {
  final _amountController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _addMoneyToWallet() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<DeliveryAuthProvider>(context, listen: false);
      final deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);
      
      await deliveryProvider.addMoneyToCustomerWallet(
        customerId: widget.customer.id,
        amount: amount,
        deliveryBoyId: authProvider.deliveryBoy!.id,
        description: 'Cash payment collected by delivery partner',
      );

      // Update parent widget
      widget.onMoneyAdded(amount);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('₹${amount.toStringAsFixed(2)} added to ${widget.customer.name}\'s wallet'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding money: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Money to ${widget.customer.name}\'s Wallet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Balance: ₹${widget.customer.walletBalance.toStringAsFixed(2)}',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount to Add',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Text(
                'This will add cash payment to customer\'s wallet balance.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addMoneyToWallet,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Add Money'),
        ),
      ],
    );
  }
}
