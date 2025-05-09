import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'loginScreen.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'dart:async';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _platformController = TextEditingController();

  String? _selectedCountry = 'Tunisia';
  String? _selectedGender = 'Male';
  bool _isEditing = false;
  File? _profileImage;
  bool _isLoading = false;
  String? _userRole;
  bool? _shareLocation;
  StreamSubscription<Position>? _positionStream;

  final List<String> _countries = ['Tunisia', 'France', 'Germany', 'Other'];
  final List<String> _genders = ['Male', 'Female', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadUserRoleAndFixGeohash();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _fullNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _platformController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRoleAndFixGeohash() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        String role = data['role'] ?? 'employee';
        if (!data.containsKey('role') && data.containsKey('platform')) {
          role = 'agent';
          print('Warning: User ${user?.uid} has no role but has platform ${data['platform']}. Defaulting to agent. Please fix the data.');
        }

        // Check and fix geohash if location exists but geohash is missing
        final location = data['location'] as Map<String, dynamic>?;
        if (location != null &&
            location['geopoint'] != null &&
            !location.containsKey('geohash') &&
            data['shareLocation'] == true) {
          final latitude = (location['geopoint'].latitude as num).toDouble();
          final longitude = (location['geopoint'].longitude as num).toDouble();
          final geo = GeoFlutterFire();
          final geoPoint = geo.point(latitude: latitude, longitude: longitude);

          await FirebaseFirestore.instance.collection('users').doc(user?.uid).update({
            'location': {
              'geopoint': GeoPoint(latitude, longitude),
              'geohash': geoPoint.data['geohash'],
              'lastUpdated': location['lastUpdated'] ?? FieldValue.serverTimestamp(),
            },
          });
          print('Added geohash for user ${user?.uid} on login');
        }

        setState(() {
          _userRole = role;
          _platformController.text = data['platform'] ?? data['department'] ?? '';
          _shareLocation = data['shareLocation'] ?? true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User profile not found. Please sign out and sign in again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error loading user role or fixing geohash: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading profile data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startLocationUpdates() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user?.uid)
        .get();
    if (doc.exists && doc.data()!['shareLocation'] == true) {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) async {
        final geo = GeoFlutterFire();
        final geoPoint = geo.point(latitude: position.latitude, longitude: position.longitude);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .update({
          'location': {
            'geopoint': GeoPoint(position.latitude, position.longitude),
            'geohash': geoPoint.data['geohash'],
            'lastUpdated': FieldValue.serverTimestamp(),
          },
        });
      }, onError: (e) {
        print('Error in location stream: $e');
      });
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
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

  Future<void> _updateShareLocation(bool value) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .get();

      if (!doc.exists) {
        throw Exception('User document not found');
      }

      final userData = doc.data()!;
      final currentRole = userData['role'] ?? 'employee';
      final currentIsActive = userData['isActive'] ?? true;

      Map<String, dynamic> updateData = {
        'shareLocation': value,
        'role': currentRole,
        'isActive': currentIsActive,
      };

      if (value) {
        final position = await _determinePosition();
        final geo = GeoFlutterFire();
        final geoPoint = geo.point(latitude: position.latitude, longitude: position.longitude);
        updateData['location'] = {
          'geopoint': GeoPoint(position.latitude, position.longitude),
          'geohash': geoPoint.data['geohash'],
          'lastUpdated': FieldValue.serverTimestamp(),
        };
        _positionStream?.cancel();
        _positionStream = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) async {
          final geo = GeoFlutterFire();
          final geoPoint = geo.point(latitude: position.latitude, longitude: position.longitude);
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user?.uid)
              .update({
            'location': {
              'geopoint': GeoPoint(position.latitude, position.longitude),
              'geohash': geoPoint.data['geohash'],
              'lastUpdated': FieldValue.serverTimestamp(),
            },
          });
        }, onError: (e) {
          print('Error in location stream: $e');
        });
      } else {
        updateData['location'] = FieldValue.delete();
        _positionStream?.cancel();
        _positionStream = null;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .update(updateData);

      setState(() {
        _shareLocation = value;
      });
    } catch (e) {
      print('Error updating share location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating location sharing: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            onPressed: () => _toggleEditMode(),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error loading profile: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _signOut,
                    child: const Text('Sign Out and Try Again'),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No profile data found.'));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          if (!_isEditing) {
            _fullNameController.text = userData['fullName'] ?? '';
            _phoneController.text = userData['phoneNumber'] ?? '';
            _addressController.text = userData['address'] ?? '';
            _platformController.text = userData['platform'] ?? userData['department'] ?? '';
            _selectedCountry = userData['country'] ?? 'Tunisia';
            _selectedGender = userData['gender'] ?? 'Male';
            _shareLocation = userData['shareLocation'] ?? true;
          }

          return _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildProfilePicture(userData),
                const SizedBox(height: 16),
                Text(
                  userData['fullName'] ?? 'User Name',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_userRole != null) ...[
                  const SizedBox(height: 4),
                  Chip(
                    label: Text(
                      _userRole!.toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: _getRoleColor(_userRole!),
                  ),
                ],
                const SizedBox(height: 24),
                _buildEditableField('Full Name', _fullNameController, Icons.person),
                _buildEditableField('Phone Number', _phoneController, Icons.phone),
                _buildEditableField('Address', _addressController, Icons.location_on),
                _buildDropdownField(
                  'Country',
                  _selectedCountry!,
                  _countries,
                  Icons.flag,
                      (value) => setState(() => _selectedCountry = value),
                ),
                _buildDropdownField(
                  'Gender',
                  _selectedGender!,
                  _genders,
                  Icons.people,
                      (value) => setState(() => _selectedGender = value),
                ),
                if (_userRole == 'agent' || _userRole == 'moderator')
                  _buildEditableField('Platform', _platformController, Icons.build),
                SwitchListTile(
                  title: const Text('Share Location'),
                  subtitle: const Text('Allow others to see your location on the map'),
                  value: _shareLocation ?? true,
                  onChanged: (value) {
                    _updateShareLocation(value);
                  },
                  secondary: const Icon(Icons.location_on, color: Colors.blue),
                ),
                const SizedBox(height: 24),
                _buildActionButtons(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfilePicture(Map<String, dynamic> userData) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.grey[200],
          backgroundImage: _getProfileImage(userData),
          child: _profileImage == null && userData['profileImageUrl'] == null
              ? const Icon(Icons.person, size: 60, color: Colors.white)
              : null,
        ),
        if (_isEditing)
          Container(
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              onPressed: _pickProfileImage,
            ),
          ),
      ],
    );
  }

  ImageProvider? _getProfileImage(Map<String, dynamic> userData) {
    if (_profileImage != null) return FileImage(_profileImage!);
    if (userData['profileImageUrl'] != null) {
      return NetworkImage(userData['profileImageUrl']);
    }
    return null;
  }

  Widget _buildEditableField(String label, TextEditingController controller, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: _isEditing
            ? TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (label == 'Platform' &&
                (_userRole == 'agent' || _userRole == 'moderator') &&
                (value == null || value.isEmpty)) {
              return 'Please enter a platform';
            }
            return null;
          },
        )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: _isEditing
            ? null
            : Text(
          controller.text.isEmpty ? 'Not provided' : controller.text,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildDropdownField(
      String label,
      String value,
      List<String> items,
      IconData icon,
      ValueChanged<String?> onChanged,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: _isEditing
            ? DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: items.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: onChanged,
        )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: _isEditing ? null : Text(value, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.lock),
            label: const Text('CHANGE PASSWORD'),
            onPressed: _showChangePasswordDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('SIGN OUT'),
            onPressed: _signOut,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'moderator':
        return Colors.orange;
      case 'agent':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  Future<void> _toggleEditMode() async {
    if (_isEditing) {
      setState(() => _isLoading = true);
      try {
        await _saveProfileData();
      } finally {
        setState(() => _isLoading = false);
      }
    }
    setState(() => _isEditing = !_isEditing);
  }

  Future<void> _saveProfileData() async {
    try {
      String? profileImageUrl;
      if (_profileImage != null) {
        profileImageUrl = await _uploadProfileImage(_profileImage!);
      }

      final updateData = {
        'fullName': _fullNameController.text,
        'phoneNumber': _phoneController.text,
        'address': _addressController.text,
        'country': _selectedCountry,
        'gender': _selectedGender,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (_userRole == 'agent' || _userRole == 'moderator') {
        if (_platformController.text.isEmpty) {
          throw Exception('Platform is required for agent or moderator roles');
        }
        updateData['platform'] = _platformController.text;
      } else {
        updateData['platform'] = FieldValue.delete();
        updateData['department'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .update(updateData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() => _profileImage = File(pickedFile.path));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String> _uploadProfileImage(File imageFile) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user?.uid}.jpg');
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newPasswordController.text.isEmpty ||
                    confirmPasswordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in both fields'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (newPasswordController.text != confirmPasswordController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Passwords do not match'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  await user!.updatePassword(newPasswordController.text);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password updated successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update password: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signOut() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'isActive': false,
          'lastActive': FieldValue.serverTimestamp(),
        });
      }
      _positionStream?.cancel();
      _positionStream = null;
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginScreen()),
            (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to sign out: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}