import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import '../models/ticket_model.dart';

class CreateTicketScreen extends StatefulWidget {
  final Ticket? ticket;

  const CreateTicketScreen({Key? key, this.ticket}) : super(key: key);

  @override
  _CreateTicketScreenState createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  String _selectedPriority = 'medium';
  String? _selectedPlatform;
  String? _selectedEquipment;
  String? _selectedAgent;
  List<String> _platforms = [];
  Map<String, List<String>> _equipmentMap = {};
  Map<String, String> _platformIdMap = {};
  final List<String> _priorities = ['low', 'medium', 'high', 'critical'];
  List<Map<String, String>> _nearbyAgents = [];
  final double _proximityRadiusMiles = 15.0;

  final Location _locationService = Location();
  final GeoFlutterFire _geo = GeoFlutterFire();
  GeoPoint? _currentPosition;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));

    if (widget.ticket != null) {
      _titleController.text = widget.ticket!.title;
      _descriptionController.text = widget.ticket!.description;
      _selectedPriority = widget.ticket!.priority.toString().split('.').last;
      _selectedPlatform = widget.ticket!.platform;
      _selectedEquipment = widget.ticket!.equipment;
      _selectedAgent = widget.ticket!.assignedTo;
    }
    _loadPlatforms();
    _getCurrentLocation();
    _animationController.forward();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
        if (!serviceEnabled) return;
      }

      PermissionStatus permission = await _locationService.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await _locationService.requestPermission();
        if (permission != PermissionStatus.granted) return;
      }

      final locationData = await _locationService.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _currentPosition = GeoPoint(locationData.latitude!, locationData.longitude!);
        });
      }
    } catch (e) {
      print('Location error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to get location: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _loadPlatforms() async {
    try {
      final platformsSnapshot = await FirebaseFirestore.instance.collection('platforms').get();
      setState(() {
        for (var doc in platformsSnapshot.docs) {
          String designation = doc.data()['designation'] as String;
          _platforms.add(designation);
          _platformIdMap[designation] = doc.id;
        }
      });
      if (_selectedPlatform != null) {
        await _loadEquipmentForPlatform(_selectedPlatform!);
        await _loadNearbyAgents(_selectedPlatform!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load platforms: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _loadEquipmentForPlatform(String platform) async {
    try {
      final platformId = _platformIdMap[platform];
      if (platformId == null) return;
      final equipmentSnapshot = await FirebaseFirestore.instance
          .collection('platforms/$platformId/equipment')
          .get();
      setState(() {
        _equipmentMap[platform] = equipmentSnapshot.docs
            .map((doc) => doc.data()['designation'] as String)
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load equipment: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _loadNearbyAgents(String platform) async {
    if (_currentPosition == null) return;

    try {
      final center = _geo.point(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
      );

      final radiusKm = _proximityRadiusMiles * 1.60934;
      final query = FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'agent')
          .where('platform', isEqualTo: platform)
          .where('shareLocation', isEqualTo: true)
          .where('isActive', isEqualTo: true)
          .where('location', isNotEqualTo: null);

      print('Fetching nearby agents for platform: $platform, radius: $radiusKm km');

      final nearbyUsers = await _geo
          .collection(collectionRef: query)
          .within(
        center: center,
        radius: radiusKm,
        field: 'location',
        strictMode: false,
      )
          .first;

      setState(() {
        _nearbyAgents = nearbyUsers
            .where((doc) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          return data['isActive'] == true && data['shareLocation'] == true;
        })
            .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['nickName'] as String? ?? data['fullName'] as String? ?? 'Agent ${doc.id}',
          };
        })
            .toList();
        print('Nearby agents: $_nearbyAgents');
      });
    } catch (e) {
      print('Error fetching nearby agents: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load nearby agents: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
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
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text(
                  widget.ticket == null ? 'Create New Ticket' : 'Edit Ticket',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 24,
                    color: Theme.of(context).colorScheme.onBackground,
                  ),
                ),
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ticket Details Card
                        SlideTransition(
                          position: _slideAnimation,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              color: Theme.of(context).colorScheme.surface,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ticket Details',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Semantics(
                                      label: 'Ticket title input, required',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Title',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _titleController,
                                            readOnly: widget.ticket != null,
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Theme.of(context).colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Enter title',
                                              hintStyle: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context).colorScheme.surface,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide.none,
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(
                                                  color: Theme.of(context).colorScheme.primary,
                                                  width: 1,
                                                ),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            ),
                                            validator: (value) {
                                              if (value == null || value.isEmpty) {
                                                return 'Title is required';
                                              }
                                              return null;
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Semantics(
                                      label: 'Ticket description input, required',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Description',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _descriptionController,
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Theme.of(context).colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Enter description',
                                              hintStyle: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context).colorScheme.surface,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide.none,
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(
                                                  color: Theme.of(context).colorScheme.primary,
                                                  width: 1,
                                                ),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              alignLabelWithHint: true,
                                            ),
                                            maxLines: 5,
                                            validator: (value) {
                                              if (value == null || value.isEmpty) {
                                                return 'Description is required';
                                              }
                                              return null;
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Semantics(
                                      label: 'Priority dropdown, required',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Priority',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            value: _selectedPriority,
                                            decoration: InputDecoration(
                                              hintText: 'Select priority',
                                              hintStyle: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context).colorScheme.surface,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide.none,
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(
                                                  color: Theme.of(context).colorScheme.primary,
                                                  width: 1,
                                                ),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            ),
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Theme.of(context).colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            dropdownColor: Theme.of(context).colorScheme.surface,
                                            icon: Icon(
                                              Icons.arrow_drop_down,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            isExpanded: true,
                                            selectedItemBuilder: (context) => _priorities.map((priority) {
                                              return Text(
                                                priority[0].toUpperCase() + priority.substring(1),
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              );
                                            }).toList(),
                                            items: _priorities.map((priority) {
                                              return DropdownMenuItem<String>(
                                                value: priority,
                                                child: Row(
                                                  children: [
                                                    _getPriorityIcon(priority),
                                                    const SizedBox(width: 16),
                                                    Text(
                                                      priority[0].toUpperCase() + priority.substring(1),
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 14,
                                                        color: Theme.of(context).colorScheme.onSurface,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (value) {
                                              setState(() {
                                                _selectedPriority = value!;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Platform & Equipment Card
                        SlideTransition(
                          position: _slideAnimation,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              color: Theme.of(context).colorScheme.surface,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Platform & Equipment',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Semantics(
                                      label: 'Platform dropdown, required',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Platform',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            value: _selectedPlatform,
                                            decoration: InputDecoration(
                                              hintText: 'Select platform',
                                              hintStyle: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context).colorScheme.surface,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide.none,
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(
                                                  color: Theme.of(context).colorScheme.primary,
                                                  width: 1,
                                                ),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            ),
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Theme.of(context).colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            dropdownColor: Theme.of(context).colorScheme.surface,
                                            icon: Icon(
                                              Icons.arrow_drop_down,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            isExpanded: true,
                                            selectedItemBuilder: (context) => _platforms.map((platform) {
                                              return Text(
                                                platform,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              );
                                            }).toList(),
                                            items: _platforms.map((platform) {
                                              return DropdownMenuItem<String>(
                                                value: platform,
                                                child: Text(
                                                  platform,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Theme.of(context).colorScheme.onSurface,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (value) async {
                                              setState(() {
                                                _selectedPlatform = value;
                                                _selectedEquipment = null;
                                                _selectedAgent = null;
                                                _equipmentMap[value!] = [];
                                                _nearbyAgents = [];
                                              });
                                              await _loadEquipmentForPlatform(value!);
                                              await _loadNearbyAgents(value);
                                            },
                                            validator: (value) {
                                              if (value == null) {
                                                return 'Platform is required';
                                              }
                                              return null;
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_selectedPlatform != null && _equipmentMap[_selectedPlatform]?.isNotEmpty == true) ...[
                                      const SizedBox(height: 16),
                                      Semantics(
                                        label: 'Equipment dropdown, optional',
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Equipment',
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                            Text(
                                              'Optional',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w400,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            DropdownButtonFormField<String>(
                                              value: _selectedEquipment,
                                              decoration: InputDecoration(
                                                hintText: 'Select equipment',
                                                hintStyle: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                                filled: true,
                                                fillColor: Theme.of(context).colorScheme.surface,
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide.none,
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: Theme.of(context).colorScheme.primary,
                                                    width: 1,
                                                  ),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              ),
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Theme.of(context).colorScheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              dropdownColor: Theme.of(context).colorScheme.surface,
                                              icon: Icon(
                                                Icons.arrow_drop_down,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                              isExpanded: true,
                                              selectedItemBuilder: (context) => [
                                                const DropdownMenuItem<String>(
                                                  value: null,
                                                  child: Text('None'),
                                                ),
                                                ..._equipmentMap[_selectedPlatform!]!.map((equipment) {
                                                  return DropdownMenuItem<String>(
                                                    value: equipment,
                                                    child: Text(
                                                      equipment,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 14,
                                                        color: Theme.of(context).colorScheme.onSurface,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                      softWrap: false,
                                                    ),
                                                  );
                                                }),
                                              ].map((item) => item.child!).toList(),
                                              items: [
                                                DropdownMenuItem<String>(
                                                  value: null,
                                                  child: Text(
                                                    'None',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 14,
                                                      color: Theme.of(context).colorScheme.onSurface,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                ..._equipmentMap[_selectedPlatform!]!.map((equipment) {
                                                  return DropdownMenuItem<String>(
                                                    value: equipment,
                                                    child: Text(
                                                      equipment,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 14,
                                                        color: Theme.of(context).colorScheme.onSurface,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                      softWrap: false,
                                                    ),
                                                  );
                                                }),
                                              ],
                                              onChanged: (value) {
                                                setState(() {
                                                  _selectedEquipment = value;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_selectedPlatform != null) ...[
                          const SizedBox(height: 16),
                          // Agent Assignment Card
                          SlideTransition(
                            position: _slideAnimation,
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                color: Theme.of(context).colorScheme.surface,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Agent Assignment',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Semantics(
                                        label: 'Agent dropdown, optional',
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Assign to Nearby Agent',
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                            Text(
                                              'Optional',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w400,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            DropdownButtonFormField<String>(
                                              value: _selectedAgent,
                                              decoration: InputDecoration(
                                                hintText: 'Select nearby agent',
                                                hintStyle: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                                filled: true,
                                                fillColor: Theme.of(context).colorScheme.surface,
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide.none,
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: Theme.of(context).colorScheme.primary,
                                                    width: 1,
                                                  ),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              ),
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Theme.of(context).colorScheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              dropdownColor: Theme.of(context).colorScheme.surface,
                                              icon: Icon(
                                                Icons.arrow_drop_down,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                              isExpanded: true,
                                              selectedItemBuilder: (context) => [
                                                const DropdownMenuItem<String>(
                                                  value: null,
                                                  child: Text('None'),
                                                ),
                                                ..._nearbyAgents.map((agent) {
                                                  return DropdownMenuItem<String>(
                                                    value: agent['id'],
                                                    child: Text(
                                                      agent['name']!,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 14,
                                                        color: Theme.of(context).colorScheme.onSurface,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                      softWrap: false,
                                                    ),
                                                  );
                                                }),
                                              ].map((item) => item.child!).toList(),
                                              items: [
                                                DropdownMenuItem<String>(
                                                  value: null,
                                                  child: Text(
                                                    'None',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 14,
                                                      color: Theme.of(context).colorScheme.onSurface,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                ..._nearbyAgents.map((agent) {
                                                  return DropdownMenuItem<String>(
                                                    value: agent['id'],
                                                    child: Text(
                                                      agent['name']!,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 14,
                                                        color: Theme.of(context).colorScheme.onSurface,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                      softWrap: false,
                                                    ),
                                                  );
                                                }),
                                              ],
                                              onChanged: (value) {
                                                setState(() {
                                                  _selectedAgent = value;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const Spacer(),
                    Semantics(
                      label: widget.ticket == null ? 'Submit ticket button' : 'Update ticket button',
                      child: AnimatedScale(
                        scale: 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: GestureDetector(
                            onTapDown: (_) => setState(() {}),
                            onTapUp: (_) => _submitTicket(),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary.withOpacity(0.9),
                                    Theme.of(context).colorScheme.secondary.withOpacity(0.9),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _isSubmitting
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                                    : Text(
                                  widget.ticket == null ? 'Submit Ticket' : 'Update Ticket',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getPriorityIcon(String priority) {
    switch (priority) {
      case 'low':
        return const Icon(Icons.flag, color: Colors.green, size: 20);
      case 'medium':
        return const Icon(Icons.flag, color: Colors.blue, size: 20);
      case 'high':
        return const Icon(Icons.flag, color: Colors.orange, size: 20);
      case 'critical':
        return const Icon(Icons.flag, color: Colors.red, size: 20);
      default:
        return const Icon(Icons.flag, size: 20);
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!userDoc.exists) {
        throw Exception('User data not found');
      }
      final userData = userDoc.data() ?? {};
      final userName = userData['nickName'] as String? ?? userData['fullName'] as String? ?? 'Unknown';

      final normalizedPlatform = _selectedPlatform!;

      if (widget.ticket == null) {
        // Create a new ticket
        final newTicket = Ticket(
          id: '',
          title: _titleController.text,
          description: _descriptionController.text,
          status: 'open',
          priority: _selectedPriority,
          platform: normalizedPlatform,
          platformName: normalizedPlatform,
          equipment: _selectedEquipment,
          equipmentName: _selectedEquipment,
          createdBy: user.uid,
          createdByName: userName,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          firstResponseAt: null,
          resolvedAt: null,
          assignedTo: _selectedAgent,
          reassigned: false,
        );

        final ticketData = newTicket.toFirestore()
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp();

        print('Creating ticket with data: $ticketData');

        await FirebaseFirestore.instance.collection('tickets').add(ticketData);
      } else {
        // Update existing ticket
        final ticketRef = FirebaseFirestore.instance.collection('tickets').doc(widget.ticket!.id);
        final currentTicketDoc = await ticketRef.get();
        final currentTicket = Ticket.fromFirestore(currentTicketDoc);

        final ticketData = <String, dynamic>{
          'description': _descriptionController.text,
          'priority': _selectedPriority,
          'platform': normalizedPlatform,
          'platformName': normalizedPlatform,
          'updatedAt': FieldValue.serverTimestamp(),
          'assignedTo': _selectedAgent,
        };

        if (_selectedEquipment != null) {
          ticketData['equipment'] = _selectedEquipment;
          ticketData['equipmentName'] = _selectedEquipment;
        } else {
          ticketData.remove('equipment');
          ticketData.remove('equipmentName');
        }

        print('Updating ticket with data: $ticketData');

        await ticketRef.update(ticketData);
      }

      Navigator.pop(context, true);
    } catch (e) {
      String errorMessage;
      if (e.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied: You may not have the necessary role to perform this action.';
      } else if (e.toString().contains('network')) {
        errorMessage = 'Network error: Please check your internet connection and try again.';
      } else {
        errorMessage = 'Error: ${e.toString()}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage, style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }
}