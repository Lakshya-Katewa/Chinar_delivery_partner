import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/delivery_auth_provider.dart';
import 'providers/delivery_provider.dart';
import 'screens/delivery_login_screen.dart';
import 'screens/delivery_dashboard_screen.dart';
import 'screens/delivery_orders_screen.dart';
import 'screens/delivery_customers_screen.dart';
import 'screens/delivery_profile_screen.dart';
import 'screens/delivery_route_screen.dart';
import 'screens/delivery_map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const DeliveryBoyApp());
}

class DeliveryBoyApp extends StatelessWidget {
  const DeliveryBoyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeliveryAuthProvider()),
        ChangeNotifierProvider(create: (_) => DeliveryProvider()),
      ],
      child: MaterialApp(
        title: 'Delivery Partner App',
        theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const AuthWrapper(),
        routes: {
          '/delivery-login': (context) => const DeliveryLoginScreen(),
          '/delivery-dashboard': (context) => const DeliveryDashboardScreen(),
          '/delivery-orders': (context) => const DeliveryOrdersScreen(),
          '/delivery-customers': (context) => const DeliveryCustomersScreen(),
          '/delivery-profile': (context) => const DeliveryProfileScreen(),
          '/delivery-route': (context) => const DeliveryRouteScreen(),
          '/delivery-map': (context) => const DeliveryMapScreen(), // Added route for delivery map screen
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Check if user is already logged in
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DeliveryAuthProvider>(context, listen: false).checkAuthState();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeliveryAuthProvider>(
      builder: (context, authProvider, child) {
        // Show loading screen while checking auth state
        if (authProvider.isLoading) {
          return Scaffold(
            backgroundColor: Colors.green.shade50,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.delivery_dining,
                      size: 60,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Delivery Partner',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CircularProgressIndicator(
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Navigate based on authentication state
        if (authProvider.isAuthenticated) {
          return const DeliveryDashboardScreen();
        } else {
          return const DeliveryLoginScreen();
        }
      },
    );
  }
}
