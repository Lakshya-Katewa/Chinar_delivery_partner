import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_boy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeliveryAuthProvider with ChangeNotifier {
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyDeliveryBoyId = 'delivery_boy_id';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DeliveryBoy? _deliveryBoy;
  bool _isLoading = false;
  String? _error;

  DeliveryBoy? get deliveryBoy => _deliveryBoy;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _deliveryBoy != null;

  Future<void> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        await _loadDeliveryBoyData(credential.user!.uid);
        
        // Save auth state if login successful
        if (_deliveryBoy != null) {
          await _saveAuthState(credential.user!.uid);
        }
      }
    } on FirebaseAuthException catch (e) {
      _error = _getAuthErrorMessage(e.code);
    } catch (e) {
      _error = 'An unexpected error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadDeliveryBoyData(String uid) async {
    try {
      final doc = await _firestore.collection('delivery_boys').doc(uid).get();
      
      if (doc.exists) {
        _deliveryBoy = DeliveryBoy.fromFirestore(doc);
        
        if (!_deliveryBoy!.isActive) {
          _error = 'Your account has been deactivated. Please contact admin.';
          _deliveryBoy = null;
          await _auth.signOut();
        }
      } else {
        _error = 'Delivery boy profile not found. Please contact admin.';
        await _auth.signOut();
      }
    } catch (e) {
      _error = 'Error loading profile data';
      await _auth.signOut();
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _clearSavedAuth(); // Clear saved authentication
      _deliveryBoy = null;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Error signing out';
      notifyListeners();
    }
  }

  Future<void> updateLocation(double latitude, double longitude) async {
    if (_deliveryBoy == null) return;

    try {
      await _firestore.collection('delivery_boys').doc(_deliveryBoy!.id).update({
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _deliveryBoy = DeliveryBoy(
        id: _deliveryBoy!.id,
        name: _deliveryBoy!.name,
        email: _deliveryBoy!.email,
        phone: _deliveryBoy!.phone,
        assignedAreas: _deliveryBoy!.assignedAreas,
        isActive: _deliveryBoy!.isActive,
        latitude: latitude,
        longitude: longitude,
        profileImageUrl: _deliveryBoy!.profileImageUrl,
        createdAt: _deliveryBoy!.createdAt,
        updatedAt: DateTime.now(), 
        commissionPerDelivery: _deliveryBoy!.commissionPerDelivery,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later';
      default:
        return 'Login failed. Please try again';
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Check if user is already logged in
  Future<void> checkAuthState() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
      final savedDeliveryBoyId = prefs.getString(_keyDeliveryBoyId);

      if (isLoggedIn && savedDeliveryBoyId != null) {
        // Check if Firebase user is still authenticated
        final currentUser = _auth.currentUser;
        if (currentUser != null && currentUser.uid == savedDeliveryBoyId) {
          await _loadDeliveryBoyData(currentUser.uid);
        } else {
          // Clear saved data if Firebase auth is invalid
          await _clearSavedAuth();
        }
      }
    } catch (e) {
      debugPrint('Error checking auth state: $e');
      await _clearSavedAuth();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Save authentication state
  Future<void> _saveAuthState(String deliveryBoyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsLoggedIn, true);
      await prefs.setString(_keyDeliveryBoyId, deliveryBoyId);
    } catch (e) {
      debugPrint('Error saving auth state: $e');
    }
  }

  // Clear saved authentication
  Future<void> _clearSavedAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyIsLoggedIn);
      await prefs.remove(_keyDeliveryBoyId);
    } catch (e) {
      debugPrint('Error clearing auth state: $e');
    }
  }
}
