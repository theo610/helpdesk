import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geoflutterfire3/geoflutterfire3.dart';
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
          SnackBar(content: Text('Location error: ${e.toString()}')),
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
            SnackBar(content: Text('Failed to update location: ${e.toString()}')),
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

    print('Starting stream with center: ${center.data}, radius: $radiusKm km');
    print('Query filters: shareLocation=true, isActive=true, location!=null');
    _usersStream = _geo
        .collection(collectionRef: query)
        .within(
      center: center,
      radius: radiusKm,
      field: 'location',
      strictMode: false,
    )
        .listen((List<DocumentSnapshot> documents) {
      print('Fetched documents: ${documents.map((doc) => doc.id).toList()}');
      documents.forEach((doc) {
        final data = doc.data() as Map<String, dynamic>;
        print('Document ${doc.id} data: $data');
        print('Document ${doc.id} - isActive: ${data['isActive']}, shareLocation: ${data['shareLocation']}');
      });
      _updateMarkers(documents);
    }, onError: (e) {
      print('Firestore error: $e');
      setState(() => _firestoreDenied = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data access error: ${e.toString()}')),
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
      final meetsCriteria = doc.id != currentUserId && isActive && shareLocation;
      if (!meetsCriteria) {
        print('Excluding document ${doc.id} - isActive: $isActive, shareLocation: $shareLocation');
      }
      return meetsCriteria;
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
      final lastActive = data['lastActive'] as Timestamp?;
      final lastActiveText = lastActive != null
          ? 'Active ${_timeAgo(lastActive.toDate())}'
          : 'Active now';

      print('Creating marker for $userId - userName: "$userName", lastActiveText: "$lastActiveText"');

      return Marker(
        point: latlong.LatLng(lat, lng),
        width: 100,
        height: 90,
        child: GestureDetector(
          onTap: () => _startChat(userId, userName),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_pin,
                color: Colors.blue,
                size: 36,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
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
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.grey,
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
          const SnackBar(content: Text('You must be logged in to start a chat')),
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
          ),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _firestoreDenied ? Icons.cloud_off : Icons.location_off,
            size: 48,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            _firestoreDenied
                ? 'Firestore permissions denied'
                : 'Location permission required',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please check your settings',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _initializeLocationAndFetchUsers,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildMapContent() {
    return FlutterMap(
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
            ..._markers,
            if (_currentPosition != null)
              Marker(
                point: _currentPosition!,
                width: 80,
                height: 60,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_pin,
                      color: Colors.red,
                      size: 36,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'You',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Users'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeLocationAndFetchUsers,
            tooltip: 'Refresh',
          ),
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: () => _mapController.move(_currentPosition!, 12),
              tooltip: 'My Location',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_locationDenied || _firestoreDenied)
          ? _buildPermissionDeniedView()
          : _currentPosition == null
          ? const Center(child: Text('Location unattainable'))
          : _buildMapContent(),
    );
  }
}