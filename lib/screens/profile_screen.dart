import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'loginScreen.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart' show rootBundle;

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();

  String? _selectedCountry = 'Tunisia';
  String? _selectedGender = 'Male';
  bool _isEditing = false;
  File? _profileImage;
  bool _isLoading = false;
  String? _userRole;

  final List<String> _countries = ['Tunisia', 'France', 'Germany', 'Other'];
  final List<String> _genders = ['Male', 'Female', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user?.uid)
        .get();

    if (doc.exists) {
      setState(() {
        _userRole = doc.data()?['role'] ?? 'employee';
        _departmentController.text = doc.data()?['department'] ?? '';
      });
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

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No profile data found.'));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          if (!_isEditing) {
            _fullNameController.text = userData['fullName'] ?? '';
            _phoneController.text = userData['phoneNumber'] ?? '';
            _addressController.text = userData['address'] ?? '';
            _selectedCountry = userData['country'] ?? 'Tunisia';
            _selectedGender = userData['gender'] ?? 'Male';
          }

          return _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Profile Picture
                _buildProfilePicture(userData),
                const SizedBox(height: 16),

                // User Name
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

                // Editable Fields
                _buildEditableField('Full Name', _fullNameController, Icons.person),
                _buildEditableField('Phone Number', _phoneController, Icons.phone),
                _buildEditableField('Address', _addressController, Icons.location_on),

                // Country Dropdown
                _buildDropdownField(
                  'Country',
                  _selectedCountry!,
                  _countries,
                  Icons.flag,
                      (value) => _selectedCountry = value,
                ),

                // Gender Dropdown
                _buildDropdownField(
                  'Gender',
                  _selectedGender!,
                  _genders,
                  Icons.people,
                      (value) => _selectedGender = value,
                ),

                // Department Field (for agents/moderators)
                if (_userRole == 'agent' || _userRole == 'moderator')
                  _buildEditableField('Department', _departmentController, Icons.work),

                const SizedBox(height: 24),

                // Action Buttons
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

      // Add department only for agents/moderators
      if (_userRole == 'agent' || _userRole == 'moderator') {
        updateData['department'] = _departmentController.text;
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

                if (newPasswordController.text !=
                    confirmPasswordController.text) {
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