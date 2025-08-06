class DeliveryStats {
  final int todayDelivered;
  final int todayPending;
  final double todayEarnings;
  final int monthlyDelivered;
  final double monthlyEarnings;
  final double totalDistance;
  final double commissionPerDelivery; // Add commission rate for reference
  final double bonusPerDelivery; // Add bonus rate for reference

  DeliveryStats({
    required this.todayDelivered,
    required this.todayPending,
    required this.todayEarnings,
    required this.monthlyDelivered,
    required this.monthlyEarnings,
    required this.totalDistance,
    required this.commissionPerDelivery,
    this.bonusPerDelivery = 0.0,
  });

  int get todayTotal => todayDelivered + todayPending;
  double get todayCompletionRate => todayTotal > 0 ? (todayDelivered / todayTotal) * 100 : 0;
  
  // Calculate potential earnings if all pending deliveries are completed
  double get potentialTodayEarnings {
    return todayTotal * (commissionPerDelivery + bonusPerDelivery);
  }
  
  // Calculate remaining earnings from pending deliveries
  double get remainingEarnings {
    return todayPending * (commissionPerDelivery + bonusPerDelivery);
  }

  // Get earnings breakdown
  String get earningsBreakdown {
    if (bonusPerDelivery > 0) {
      final commission = todayDelivered * commissionPerDelivery;
      final bonus = todayDelivered * bonusPerDelivery;
      return 'Commission: ₹${commission.toStringAsFixed(0)} + Bonus: ₹${bonus.toStringAsFixed(0)}';
    }
    return '${todayDelivered} deliveries × ₹${commissionPerDelivery.toStringAsFixed(0)}';
  }
}
