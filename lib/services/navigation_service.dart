import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

class NavigationService {
  // Get current location with better error handling
  static Future<Position?> getCurrentLocation() async {
    try {
      // Check location permissions first
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
        return null;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return null;
      }

      // Get current position with high accuracy
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      debugPrint('Got current location: ${position.latitude}, ${position.longitude}');
      return position;
      
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  // Launch external navigation apps with current location
  static Future<void> openNavigation({
    required double destinationLat,
    required double destinationLng,
    required String destinationName,
    Position? currentLocation,
  }) async {
    try {
      // Validate destination coordinates first
      if (destinationLat == 0.0 && destinationLng == 0.0) {
        throw Exception('Invalid destination coordinates (0,0). Please check the delivery address.');
      }

      if (destinationLat.abs() < 0.001 && destinationLng.abs() < 0.001) {
        throw Exception('Invalid destination coordinates. Please check the delivery address.');
      }

      // Always try to get fresh current location first
      Position? freshLocation = await getCurrentLocation();
      final locationToUse = freshLocation ?? currentLocation;
      
      debugPrint('=== NAVIGATION DEBUG ===');
      debugPrint('Destination: $destinationLat, $destinationLng ($destinationName)');
      debugPrint('Destination type: ${destinationLat.runtimeType}, ${destinationLng.runtimeType}');
      debugPrint('Current location: ${locationToUse?.latitude}, ${locationToUse?.longitude}');
      debugPrint('Using fresh location: ${freshLocation != null}');
      debugPrint('Destination valid: ${!(destinationLat == 0.0 && destinationLng == 0.0)}');

      // Validate current location
      if (locationToUse != null) {
        if (locationToUse.latitude == 0.0 && locationToUse.longitude == 0.0) {
          debugPrint('WARNING: Current location is (0,0) - this will cause navigation issues');
        }
      }

      // Try different navigation apps in order of preference
      final navigationOptions = [
        _buildGoogleMapsUrl(destinationLat, destinationLng, destinationName, locationToUse),
        _buildWazeUrl(destinationLat, destinationLng, locationToUse),
        _buildAppleMapsUrl(destinationLat, destinationLng, destinationName, locationToUse),
      ];

      bool launched = false;
      
      for (String url in navigationOptions) {
        debugPrint('Trying navigation URL: $url');
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launched = true;
          debugPrint('Successfully launched navigation with: $url');
          break;
        }
      }

      if (!launched) {
        // Fallback to browser-based Google Maps with directions
        String fallbackUrl;
        if (locationToUse != null && 
            !(locationToUse.latitude == 0.0 && locationToUse.longitude == 0.0)) {
          fallbackUrl = 'https://www.google.com/maps/dir/${locationToUse.latitude},${locationToUse.longitude}/$destinationLat,$destinationLng';
        } else {
          fallbackUrl = 'https://www.google.com/maps/search/?api=1&query=$destinationLat,$destinationLng';
        }
      
        debugPrint('Using fallback URL: $fallbackUrl');
        final uri = Uri.parse(fallbackUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error opening navigation: $e');
      throw Exception('Could not open navigation app: $e');
    }
  }

  static String _buildGoogleMapsUrl(
    double destLat, 
    double destLng, 
    String destName,
    Position? currentLocation,
  ) {
    // Validate destination coordinates
    if (destLat == 0.0 && destLng == 0.0) {
      debugPrint('ERROR: Destination coordinates are (0,0)');
      return 'geo:0,0?q=Invalid+Location';
    }

    if (currentLocation != null && 
        !(currentLocation.latitude == 0.0 && currentLocation.longitude == 0.0)) {
      // With valid current location for turn-by-turn navigation
      // Use the directions URL format for better navigation
      return 'https://www.google.com/maps/dir/${currentLocation.latitude},${currentLocation.longitude}/$destLat,$destLng';
    } else {
      // Without current location - just show destination
      return 'geo:$destLat,$destLng?q=$destLat,$destLng($destName)';
    }
  }

  static String _buildWazeUrl(double destLat, double destLng, Position? currentLocation) {
    // Validate destination coordinates
    if (destLat == 0.0 && destLng == 0.0) {
      debugPrint('ERROR: Destination coordinates are (0,0) for Waze');
      return 'waze://?ll=0,0&navigate=no';
    }

    return 'waze://?ll=$destLat,$destLng&navigate=yes';
  }

  static String _buildAppleMapsUrl(double destLat, double destLng, String destName, Position? currentLocation) {
    // Validate destination coordinates
    if (destLat == 0.0 && destLng == 0.0) {
      debugPrint('ERROR: Destination coordinates are (0,0) for Apple Maps');
      return 'maps://?daddr=0,0';
    }

    if (currentLocation != null && 
        !(currentLocation.latitude == 0.0 && currentLocation.longitude == 0.0)) {
      // Apple Maps with current location for directions
      return 'maps://?saddr=${currentLocation.latitude},${currentLocation.longitude}&daddr=$destLat,$destLng';
    } else {
      // Apple Maps without current location
      return 'maps://?daddr=$destLat,$destLng';
    }
  }

  // Show navigation options dialog with coordinate validation
  static Future<void> showNavigationOptions({
    required BuildContext context,
    required double destinationLat,
    required double destinationLng,
    required String destinationName,
    Position? currentLocation,
  }) async {
    // Validate coordinates before showing dialog
    if (destinationLat == 0.0 && destinationLng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid delivery address coordinates. Please contact support.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
              'Navigate to $destinationName',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Show coordinates for debugging
            Text(
              'Destination: ${destinationLat.toStringAsFixed(6)}, ${destinationLng.toStringAsFixed(6)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            if (currentLocation != null)
              Text(
                'From: ${currentLocation.latitude.toStringAsFixed(6)}, ${currentLocation.longitude.toStringAsFixed(6)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade600,
                ),
              ),
            
            const SizedBox(height: 24),

            // Google Maps Option
            _buildNavigationOption(
              context: context,
              icon: Icons.map,
              title: 'Google Maps',
              subtitle: 'Turn-by-turn navigation',
              color: Colors.blue,
              onTap: () async {
                Navigator.pop(context);
                try {
                  await openNavigation(
                    destinationLat: destinationLat,
                    destinationLng: destinationLng,
                    destinationName: destinationName,
                    currentLocation: currentLocation,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Navigation error: $e')),
                    );
                  }
                }
              },
            ),
            
            const SizedBox(height: 12),

            // Waze Option
            _buildNavigationOption(
              context: context,
              icon: Icons.navigation,
              title: 'Waze',
              subtitle: 'Real-time traffic updates',
              color: Colors.cyan,
              onTap: () async {
                Navigator.pop(context);
                try {
                  final url = _buildWazeUrl(destinationLat, destinationLng, currentLocation);
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    throw Exception('Waze not available');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Waze error: $e')),
                    );
                  }
                }
              },
            ),
            
            const SizedBox(height: 12),

            // Browser Maps Option
            _buildNavigationOption(
              context: context,
              icon: Icons.public,
              title: 'Browser Maps',
              subtitle: 'Open in web browser',
              color: Colors.green,
              onTap: () async {
                Navigator.pop(context);
                String url;
                if (currentLocation != null && 
                    !(currentLocation.latitude == 0.0 && currentLocation.longitude == 0.0)) {
                  url = 'https://www.google.com/maps/dir/${currentLocation.latitude},${currentLocation.longitude}/$destinationLat,$destinationLng';
                } else {
                  url = 'https://www.google.com/maps/dir/?api=1&destination=$destinationLat,$destinationLng';
                }
                final uri = Uri.parse(url);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static Widget _buildNavigationOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withOpacity(0.3)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  // Calculate estimated time and distance using free routing service
  static Future<Map<String, dynamic>?> getRouteInfo({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      // Validate coordinates
      if ((startLat == 0.0 && startLng == 0.0) || (endLat == 0.0 && endLng == 0.0)) {
        debugPrint('Invalid coordinates for route calculation');
        return null;
      }

      final distance = Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
      final distanceKm = distance / 1000;
      
      // Rough estimation: average speed 30 km/h in city
      final estimatedTimeMinutes = (distanceKm / 30) * 60;
      
      return {
        'distance': distanceKm,
        'duration': estimatedTimeMinutes,
        'distanceText': '${distanceKm.toStringAsFixed(1)} km',
        'durationText': '${estimatedTimeMinutes.toStringAsFixed(0)} min',
      };
    } catch (e) {
      debugPrint('Error getting route info: $e');
      return null;
    }
  }
}
