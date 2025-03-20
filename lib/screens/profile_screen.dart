import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'loginScreen.dart'; // Import the LoginScreen
import 'package:firebase_storage/firebase_storage.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser; // Get the current user
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();

  bool _isEditing = false;
  File? _profileImage; // To store the selected image file

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            onPressed: () {
              setState(() {
                if (_isEditing) {
                  _saveProfileData();
                }
                _isEditing = !_isEditing;
              });
            },
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
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('No profile data found.'));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;

          // Populate controllers with existing data
          if (!_isEditing) {
            _fullNameController.text = userData['fullName'] ?? '';
            _phoneNumberController.text = userData['phoneNumber'] ?? '';
            _addressController.text = userData['address'] ?? '';
            _countryController.text = userData['country'] ?? '';
            _genderController.text = userData['gender'] ?? '';
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // User Profile Picture and Name
                GestureDetector(
                  onTap: _isEditing ? _pickProfileImage : null, // Allow image change only in edit mode
                  child: CircleAvatar(
                    radius: 60,
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!) // Use the selected image
                        : userData['profileImageUrl'] != null
                        ? NetworkImage(userData['profileImageUrl']) // Load from Firestore
                        : AssetImage('assets/images/default_profile.png') as ImageProvider, // Default image
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  userData['fullName'] ?? 'User Name', // Display the user's name
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),

                // Display Profile Data (Editable if _isEditing is true)
                _buildEditableField('Full Name', _fullNameController, Icons.person),
                _buildEditableField('Phone Number', _phoneNumberController, Icons.phone),
                _buildEditableField('Address', _addressController, Icons.location_on),
                _buildEditableField('Country', _countryController, Icons.flag),
                _buildEditableField('Gender', _genderController, Icons.people),
                SizedBox(height: 20),

                // Change Password Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _showChangePasswordDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue, // Blue color for the button
                    ),
                    child: Text('Change Password'),
                  ),
                ),
                SizedBox(height: 20),

                // Disconnect Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await FirebaseAuth.instance.signOut(); // Sign out the user
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => LoginScreen()),
                        );
                      } catch (e) {
                        print('Error during logout: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Logout failed. Please try again.')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey, // Grey color for disconnect button
                    ),
                    child: Text('Disconnect'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Function to build an editable field
  Widget _buildEditableField(String label, TextEditingController controller, IconData icon) {
    return ListTile(
      leading: Icon(icon),
      title: _isEditing
          ? TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
      )
          : Text(label),
      subtitle: _isEditing ? null : Text(controller.text.isEmpty ? 'Not provided' : controller.text),
    );
  }

  // Function to save profile data to Firestore
  Future<void> _saveProfileData() async {
    try {
      String? profileImageUrl;

      // Upload the new profile image if selected
      if (_profileImage != null) {
        profileImageUrl = await _uploadProfileImage(_profileImage!);
      }

      await FirebaseFirestore.instance.collection('users').doc(user?.uid).update({
        'fullName': _fullNameController.text,
        'phoneNumber': _phoneNumberController.text,
        'address': _addressController.text,
        'country': _countryController.text,
        'gender': _genderController.text,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile updated successfully!')),
      );
    } catch (e) {
      print('Error updating profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile. Please try again.')),
      );
    }
  }

  // Function to pick a profile image from the gallery or camera
  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });
    }
  }

  // Function to upload the profile image to Firebase Storage
  Future<String> _uploadProfileImage(File imageFile) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user?.uid}.jpg');

      await ref.putFile(imageFile);
      final downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Error uploading image: $e');
      throw e;
    }
  }

  // Function to show a dialog for changing the password
  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final TextEditingController _newPasswordController = TextEditingController();
    final TextEditingController _confirmPasswordController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 20),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close the dialog
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (_newPasswordController.text.isEmpty || _confirmPasswordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please fill in both fields.')),
                  );
                  return;
                }

                if (_newPasswordController.text != _confirmPasswordController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Passwords do not match.')),
                  );
                  return;
                }

                try {
                  // Update password in Firebase Authentication
                  await user!.updatePassword(_newPasswordController.text.trim());

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Password updated successfully!')),
                  );

                  Navigator.pop(context); // Close the dialog
                } catch (e) {
                  print('Error updating password: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update password. Please try again.')),
                  );
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }
}