import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

class ManagePlatformsScreen extends StatefulWidget {
  const ManagePlatformsScreen({Key? key}) : super(key: key);

  @override
  _ManagePlatformsScreenState createState() => _ManagePlatformsScreenState();
}

class _ManagePlatformsScreenState extends State<ManagePlatformsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _platformController = TextEditingController();
  final TextEditingController _equipmentController = TextEditingController();
  String? _selectedPlatformId;
  bool _isLoading = false;

  List<Map<String, dynamic>> _platforms = [];
  Map<String, List<Map<String, dynamic>>> _equipmentMap = {};

  @override
  void initState() {
    super.initState();
    _loadPlatforms();
  }

  Future<void> _loadPlatforms() async {
    setState(() => _isLoading = true);
    try {
      final platformsSnapshot = await FirebaseFirestore.instance.collection('platforms').get();
      _platforms = platformsSnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'designation': doc.data()['designation'] as String,
        };
      }).toList();

      // Load equipment for each platform
      for (var platform in _platforms) {
        final equipmentSnapshot = await FirebaseFirestore.instance
            .collection('platforms/${platform['id']}/equipment')
            .get();
        _equipmentMap[platform['id']] = equipmentSnapshot.docs.map((doc) {
          return {
            'id': doc.id,
            'designation': doc.data()['designation'] as String,
          };
        }).toList();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load platforms: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addPlatform() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('platforms').add({
        'designation': _platformController.text.trim(),
      });
      _platformController.clear();
      _loadPlatforms(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Platform added successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding platform: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addEquipment(String platformId) async {
    if (_equipmentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Equipment name cannot be empty', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('platforms/$platformId/equipment')
          .add({
        'designation': _equipmentController.text.trim(),
      });
      _equipmentController.clear();
      _loadPlatforms(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Equipment added successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding equipment: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePlatform(String platformId) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('platforms').doc(platformId).delete();
      _loadPlatforms(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Platform deleted successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting platform: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEquipment(String platformId, String equipmentId) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('platforms/$platformId/equipment')
          .doc(equipmentId)
          .delete();
      _loadPlatforms(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Equipment deleted successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting equipment: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: MediaQuery.of(context).size.height,
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
        child: _isLoading
            ? Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
          ),
        )
            : AnimationLimiter(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: AnimationConfiguration.toStaggeredList(
                duration: const Duration(milliseconds: 375),
                childAnimationBuilder: (widget) => SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(child: widget),
                ),
                children: [
                  Text(
                    'Manage Platforms & Equipment',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _platformController,
                              decoration: InputDecoration(
                                labelText: 'New Platform',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                labelStyle: GoogleFonts.poppins(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a platform name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _addPlatform,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                'Add Platform',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_platforms.isEmpty)
                    Center(
                      child: Text(
                        'No platforms found.',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Platforms',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _platforms.length,
                          itemBuilder: (context, index) {
                            final platform = _platforms[index];
                            final platformId = platform['id'] as String;
                            final equipmentList = _equipmentMap[platformId] ?? [];
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: SlideAnimation(
                                verticalOffset: 50.0,
                                child: FadeInAnimation(
                                  child: Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: ExpansionTile(
                                      title: Text(
                                        platform['designation'],
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(
                                          Icons.delete,
                                          color: Theme.of(context).colorScheme.error,
                                          size: 20,
                                        ),
                                        onPressed: () => _deletePlatform(platformId),
                                        tooltip: 'Delete Platform',
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              TextFormField(
                                                controller: _equipmentController,
                                                decoration: InputDecoration(
                                                  labelText: 'New Equipment',
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  labelStyle: GoogleFonts.poppins(
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderSide: BorderSide(
                                                      color: Theme.of(context).colorScheme.primary,
                                                      width: 2,
                                                    ),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                ),
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              ElevatedButton(
                                                onPressed: () => _addEquipment(platformId),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                                ),
                                                child: Text(
                                                  'Add Equipment',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Theme.of(context).colorScheme.onPrimary,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              equipmentList.isEmpty
                                                  ? Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                                child: Text(
                                                  'No equipment assigned',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              )
                                                  : ListView.builder(
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                                itemCount: equipmentList.length,
                                                itemBuilder: (context, equipIndex) {
                                                  final equipment = equipmentList[equipIndex];
                                                  return ListTile(
                                                    contentPadding: const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 4,
                                                    ),
                                                    title: Text(
                                                      equipment['designation'],
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 14,
                                                        color: Theme.of(context).colorScheme.onSurface,
                                                      ),
                                                    ),
                                                    trailing: IconButton(
                                                      icon: Icon(
                                                        Icons.delete,
                                                        color: Theme.of(context).colorScheme.error,
                                                        size: 20,
                                                      ),
                                                      onPressed: () => _deleteEquipment(
                                                        platformId,
                                                        equipment['id'],
                                                      ),
                                                      tooltip: 'Delete Equipment',
                                                    ),
                                                  );
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
                            );
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading
            ? null
            : () async {
          setState(() => _isLoading = true);
          await _loadPlatforms();
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          Icons.refresh,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        tooltip: 'Refresh',
      ),
    );
  }

  @override
  void dispose() {
    _platformController.dispose();
    _equipmentController.dispose();
    super.dispose();
  }
}