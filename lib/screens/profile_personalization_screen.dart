import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'dart:io';
import 'role_based_main_screen.dart';
import 'waiting_for_approval_screen.dart';

class ProfilePersonalizationScreen extends StatefulWidget {
  final String uid;
  final bool isAdmin;

  const ProfilePersonalizationScreen({
    required this.uid,
    required this.isAdmin,
    Key? key,
  }) : super(key: key);

  @override
  _ProfilePersonalizationScreenState createState() => _ProfilePersonalizationScreenState();
}

class _ProfilePersonalizationScreenState extends State<ProfilePersonalizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _nickNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String _selectedCountry = 'Tunisia';
  String _selectedGender = 'Female';
  String _selectedRole = 'employee';
  String? _selectedPlatform;
  File? _profileImage;
  bool _isLoading = false;
  bool _shareLocation = true;
  List<String> _platforms = [];

  @override
  void initState() {
    super.initState();
    print('ProfilePersonalizationScreen initState: UID=${widget.uid}, isAdmin=${widget.isAdmin}');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != widget.uid) {
      print('Authentication error: No user or UID mismatch');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authentication error. Please sign in again.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    if (user.email != null) {
      _emailController.text = user.email!;
    }
    if (widget.isAdmin) {
      _selectedRole = 'admin';
    }
    _loadPlatforms();
  }

  Future<void> _loadPlatforms() async {
    print('Loading platforms for UID=${widget.uid}');
    try {
      final platformsSnapshot = await FirebaseFirestore.instance.collection('platforms').get();
      print('Platforms loaded: ${platformsSnapshot.docs.length} documents');
      setState(() {
        _platforms = platformsSnapshot.docs.map((doc) => doc.data()['designation'] as String).toList();
      });
    } catch (e) {
      print('Error loading platforms: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load platforms: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickImage() async {
    print('Picking image for UID=${widget.uid}');
    final ImagePicker picker = ImagePicker();
    final XFile? pickedImage = await picker.pickImage(source: ImageSource.gallery);

    if (pickedImage != null) {
      setState(() {
        _profileImage = File(pickedImage.path);
      });
    }
  }

  Future<String?> _uploadProfileImage(File imageFile) async {
    print('Uploading profile image for UID=${widget.uid}');
    try {
      final Reference storageReference = FirebaseStorage.instance
          .ref()
          .child('profile_pictures/${widget.uid}.jpg');

      final UploadTask uploadTask = storageReference.putFile(imageFile);
      final TaskSnapshot taskSnapshot = await uploadTask;
      final url = await taskSnapshot.ref.getDownloadURL();
      print('Image uploaded: $url');
      return url;
    } catch (e) {
      print('Error uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading image: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<Position> _determinePosition() async {
    print('Determining position for UID=${widget.uid}');
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    print('Saving profile for UID=${widget.uid}');
    try {
      setState(() => _isLoading = true);

      if (_emailController.text.isEmpty) {
        throw Exception('Email is required');
      }
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text)) {
        throw Exception('Please enter a valid email');
      }
      if (_fullNameController.text.isEmpty) {
        throw Exception('Full name is required');
      }
      if (_nickNameController.text.isEmpty) {
        throw Exception('Nickname is required');
      }
      if (_phoneNumberController.text.isEmpty) {
        throw Exception('Phone number is required');
      }
      if (_addressController.text.isEmpty) {
        throw Exception('Address is required');
      }
      if (_selectedRole.isEmpty) {
        throw Exception('Role is required');
      }
      if (_selectedRole == 'agent' || _selectedRole == 'moderator') {
        if (_selectedPlatform == null || _selectedPlatform!.isEmpty) {
          throw Exception('Platform is required for agent or moderator roles');
        }
        final platformSnapshot = await FirebaseFirestore.instance
            .collection('platforms')
            .where('designation', isEqualTo: _selectedPlatform)
            .get();
        if (platformSnapshot.docs.isEmpty) {
          throw Exception('Invalid platform. Please select a valid platform (e.g., CAO, TEST:DC & RF).');
        }
      }
      if (_selectedRole == 'admin') {
        throw Exception('Admin role cannot be set via profile personalization. Contact support.');
      }

      String? profileImageUrl;
      if (_profileImage != null) {
        profileImageUrl = await _uploadProfileImage(_profileImage!);
      }

      final userData = <String, dynamic>{
        'fullName': _fullNameController.text,
        'nickName': _nickNameController.text,
        'email': _emailController.text,
        'phoneNumber': _phoneNumberController.text,
        'address': _addressController.text,
        'country': _selectedCountry,
        'gender': _selectedGender,
        'role': _selectedRole,
        'isActive': true,
        'hasCompletedProfile': true,
        'isApproved': false,
        'shareLocation': _shareLocation,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(), // Added timestamp for profile creation
      };

      if (_selectedRole == 'agent' || _selectedRole == 'moderator') {
        userData['platform'] = _selectedPlatform!;
      }

      if (_shareLocation) {
        final position = await _determinePosition();
        final geo = GeoFlutterFire();
        final geoPoint = geo.point(latitude: position.latitude, longitude: position.longitude);
        userData['location'] = {
          'geopoint': GeoPoint(position.latitude, position.longitude),
          'geohash': geoPoint.data['geohash'],
          'lastUpdated': FieldValue.serverTimestamp(),
        };
      }

      print('Writing userData to Firestore: $userData');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .set(userData, SetOptions(merge: true));

      final user = FirebaseAuth.instance.currentUser!;
      if (user.email != _emailController.text) {
        await user.updateEmail(_emailController.text);
        print('Updated FirebaseAuth email to: ${_emailController.text}');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile submitted for admin approval!'),
          backgroundColor: Colors.green,
        ),
      );

      print('Navigating to WaitingForApprovalScreen');
      Navigator.pushReplacementNamed(context, '/waiting');
    } catch (e) {
      print('Error saving profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    print('Disposing ProfilePersonalizationScreen for UID=${widget.uid}');
    _fullNameController.dispose();
    _nickNameController.dispose();
    _emailController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('Building ProfilePersonalizationScreen for UID=${widget.uid}');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : const AssetImage('assets/default_profile.png') as ImageProvider,
                    backgroundColor: Colors.grey[200],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                      onPressed: _pickImage,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your full name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nickNameController,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.face),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your nickname';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneNumberController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _selectedCountry,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                items: const [
                  DropdownMenuItem(value: 'Tunisia', child: Text('Tunisia')),
                  DropdownMenuItem(value: 'France', child: Text('France')),
                  DropdownMenuItem(value: 'Canada', child: Text('Canada')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCountry = newValue!;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a country';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.transgender),
                ),
                items: const [
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                ],
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedGender = newValue!;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a gender';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              if (!widget.isAdmin)
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'User Role',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.work),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'employee', child: Text('Employee')),
                    DropdownMenuItem(value: 'agent', child: Text('Agent')),
                    DropdownMenuItem(value: 'moderator', child: Text('Moderator')),
                  ],
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedRole = newValue!;
                      if (_selectedRole == 'employee') {
                        _selectedPlatform = null;
                      }
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a role';
                    }
                    return null;
                  },
                ),
              if (!widget.isAdmin) const SizedBox(height: 16),

              if (widget.isAdmin)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.verified_user, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Admin Account',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.isAdmin) const SizedBox(height: 16),

              if (_selectedRole == 'agent' || _selectedRole == 'moderator')
                DropdownButtonFormField<String>(
                  value: _selectedPlatform,
                  decoration: const InputDecoration(
                    labelText: 'Platform',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.build),
                  ),
                  hint: const Text('Select Platform'),
                  items: _platforms
                      .map((platform) => DropdownMenuItem(
                    value: platform,
                    child: Text(platform),
                  ))
                      .toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedPlatform = newValue;
                    });
                  },
                  validator: (value) {
                    if ((_selectedRole == 'agent' || _selectedRole == 'moderator') && value == null) {
                      return 'Please select a platform';
                    }
                    return null;
                  },
                ),
              if (_selectedRole == 'agent' || _selectedRole == 'moderator')
                const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.home),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              SwitchListTile(
                title: const Text('Share Location'),
                subtitle: const Text('Allow others to see your location on the map'),
                value: _shareLocation,
                onChanged: (value) {
                  setState(() {
                    _shareLocation = value;
                  });
                },
                secondary: const Icon(Icons.location_on, color: Colors.blue),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    'Submit Profile for Approval',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}