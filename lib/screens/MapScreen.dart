import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../repositories/chat_repository.dart';
import 'chat_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Location _locationService = Location();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatRepository _chatRepository = ChatRepository();
  final MapController _mapController = MapController();
  final double _proximityRadiusMiles = 15.0;
  final GeoFlutterFire _geo = GeoFlutterFire();

  latlong.LatLng? _currentPosition;
  List<Marker> _markers = [];
  bool _isLoading = true;
  bool _locationDenied = false;
  bool _firestoreDenied = false;
  StreamSubscription? _usersStream;
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _initializeLocationAndFetchUsers();
  }

  Future<void> _initializeLocationAndFetchUsers() async {
    await _getCurrentLocation();
    if (!_locationDenied && _currentPosition != null) {
      _startUsersStream();
      _startLocationUpdates();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
        if (!serviceEnabled) {
          setState(() => _locationDenied = true);
          return;
        }
      }

      PermissionStatus permission = await _locationService.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await _locationService.requestPermission();
        if (permission != PermissionStatus.granted) {
          setState(() => _locationDenied = true);
          return;
        }
      }

      final locationData = await _locationService.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        await _updateUserLocation(
          locationData.latitude!,
          locationData.longitude!,
        );
      }
    } catch (e) {
      print('Location error: $e');
      setState(() => _locationDenied = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Location error: ${e.toString()}',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _updateUserLocation(double latitude, double longitude) async {
    final geoPoint = _geo.point(latitude: latitude, longitude: longitude);

    setState(() {
      _currentPosition = latlong.LatLng(latitude, longitude);
      _locationDenied = false;
    });

    if (_auth.currentUser != null) {
      try {
        await _firestore.collection('users').doc(_auth.currentUser!.uid).set({
          'location': {
            'geopoint': GeoPoint(latitude, longitude),
            'geohash': geoPoint.data['geohash'],
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          'lastActive': FieldValue.serverTimestamp(),
          'isActive': true,
          'shareLocation': true,
        }, SetOptions(merge: true));
      } catch (e) {
        print('Failed to update location: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to update location: ${e.toString()}',
                style: GoogleFonts.poppins(),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  void _startLocationUpdates() {
    _locationSubscription = _locationService.onLocationChanged.listen(
          (LocationData locationData) async {
        if (locationData.latitude != null && locationData.longitude != null) {
          await _updateUserLocation(
            locationData.latitude!,
            locationData.longitude!,
          );
        }
      },
      onError: (e) {
        print('Location update error: $e');
      },
    );
  }

  void _startUsersStream() {
    final center = _geo.point(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
    );

    final radiusKm = _proximityRadiusMiles * 1.60934;
    final query = _firestore
        .collection('users')
        .where('shareLocation', isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .where('location', isNotEqualTo: null);

    _usersStream = _geo
        .collection(collectionRef: query)
        .within(
      center: center,
      radius: radiusKm,
      field: 'location',
      strictMode: false,
    )
        .listen((List<DocumentSnapshot> documents) {
      _updateMarkers(documents);
    }, onError: (e) {
      print('Firestore error: $e');
      setState(() => _firestoreDenied = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Data access error: ${e.toString()}',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    });
  }

  void _updateMarkers(List<DocumentSnapshot> documents) {
    final currentUserId = _auth.currentUser?.uid;
    final newMarkers = documents
        .where((doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final isActive = data['isActive'] as bool? ?? false;
      final shareLocation = data['shareLocation'] as bool? ?? false;
      return doc.id != currentUserId && isActive && shareLocation;
    })
        .map(_createUserMarker)
        .whereType<Marker>()
        .toList();

    if (mounted) {
      setState(() {
        _markers = newMarkers;
        _firestoreDenied = false;
      });
    }
  }

  Marker? _createUserMarker(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final location = data['location'] as Map<String, dynamic>? ?? {};
      final geopoint = location['geopoint'];

      double? lat, lng;
      if (geopoint is GeoPoint) {
        lat = geopoint.latitude;
        lng = geopoint.longitude;
      } else if (geopoint is Map<String, dynamic>) {
        lat = (geopoint['latitude'] as num?)?.toDouble();
        lng = (geopoint['longitude'] as num?)?.toDouble();
      }

      if (lat == null || lng == null) return null;

      final userName = data['nickName'] ?? data['fullName'] ?? 'User';
      final userId = doc.id;
      final isActive = data['isActive'] as bool? ?? false;
      final lastActive = data['lastActive'] as Timestamp?;
      final lastActiveText = lastActive != null
          ? 'Active ${_timeAgo(lastActive.toDate())}'
          : 'Active now';

      return Marker(
        point: latlong.LatLng(lat, lng),
        width: 100,
        height: 90,
        child: GestureDetector(
          onTap: () => _startChat(userId, userName),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Icon(
                    Icons.location_pin,
                    color: Theme.of(context).colorScheme.primary,
                    size: 36,
                  ),
                  if (isActive)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(
                              color: Theme.of(context).colorScheme.surface,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 8,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(
                        userName,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(
                        lastActiveText,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('Error creating marker: $e');
      return null;
    }
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inSeconds < 60) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 30) return '${difference.inDays}d ago';
    return 'a long time ago';
  }

  Future<void> _startChat(String userId, String userName) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You must be logged in to start a chat',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      final conversation = await _chatRepository.getOrCreateConversation(
        userId1: currentUser.uid,
        userId2: userId,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversation.id,
            otherUserId: userId,
            otherUserName: userName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      print('Error starting chat with $userName ($userId): $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to start chat with $userName. Please try again later.',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _usersStream?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: AnimationLimiter(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 375),
            childAnimationBuilder: (widget) => SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: widget,
              ),
            ),
            children: [
              Icon(
                _firestoreDenied ? Icons.cloud_off : Icons.location_off,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                _firestoreDenied
                    ? 'Firestore permissions denied'
                    : 'Location permission required',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Please check your settings',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initializeLocationAndFetchUsers,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: Text(
                  'Retry',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapContent() {
    return AnimationLimiter(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentPosition!,
          initialZoom: 12,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.yourapp',
          ),
          MarkerLayer(
            markers: [
              ..._markers.map(
                    (marker) => Marker(
                  point: marker.point,
                  width: marker.width,
                  height: marker.height,
                  child: AnimationConfiguration.staggeredList(
                    position: _markers.indexOf(marker),
                    duration: const Duration(milliseconds: 375),
                    child: SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(
                        child: marker.child!,
                      ),
                    ),
                  ),
                ),
              ),
              if (_currentPosition != null)
                Marker(
                  point: _currentPosition!,
                  width: 80,
                  height: 60,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_pin,
                        color: Theme.of(context).colorScheme.error,
                        size: 36,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'You',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.background,
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _isLoading
                        ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                        : (_locationDenied || _firestoreDenied)
                        ? _buildPermissionDeniedView()
                        : _currentPosition == null
                        ? Center(
                      child: Text(
                        'Location unattainable',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color:
                          Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    )
                        : _buildMapContent(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Semantics(
        label: 'Refresh map',
        child: FloatingActionButton(
          onPressed: _initializeLocationAndFetchUsers,
          child: Icon(
            Icons.refresh,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          tooltip: 'Refresh Map',
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Nearby Users',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onBackground,
            ),
          ),
          if (_currentPosition != null)
            IconButton(
              icon: Icon(
                Icons.my_location,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => _mapController.move(_currentPosition!, 12),
              tooltip: 'Center on My Location',
            ),
        ],
      ),
    );
  }
}