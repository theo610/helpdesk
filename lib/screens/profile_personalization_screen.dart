import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'main_screen.dart'; // Import the MainScreen

class ProfilePersonalizationScreen extends StatefulWidget {
  final String uid;

  const ProfilePersonalizationScreen({required this.uid});

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
  String _selectedCountry = 'United States';
  String _selectedGender = 'Female';
  File? _profileImage;

  // Function to pick an image from the gallery
  Future<void> _pickImage() async {
    final ImagePicker _picker = ImagePicker();
    final XFile? pickedImage = await _picker.pickImage(source: ImageSource.gallery);

    if (pickedImage != null) {
      setState(() {
        _profileImage = File(pickedImage.path);
      });
    }
  }

  // Function to upload image to Firebase Storage and return the download URL
  Future<String?> _uploadImageToFirebaseStorage(File imageFile, String uid) async {
    try {
      final Reference storageReference = FirebaseStorage.instance
          .ref()
          .child('profile_pictures/$uid.jpg');

      final UploadTask uploadTask = storageReference.putFile(imageFile);
      final TaskSnapshot taskSnapshot = await uploadTask;
      final String downloadURL = await taskSnapshot.ref.getDownloadURL();

      return downloadURL;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  // Function to save profile data to Firestore
  Future<void> _saveProfileData() async {
    if (_formKey.currentState!.validate()) {
      String? profileImageUrl;

      // Upload the profile picture if it exists
      if (_profileImage != null) {
        profileImageUrl = await _uploadImageToFirebaseStorage(_profileImage!, widget.uid);
      }

      // Save profile data to Firestore
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'uid': widget.uid,
        'fullName': _fullNameController.text,
        'nickName': _nickNameController.text,
        'email': _emailController.text,
        'phoneNumber': _phoneNumberController.text,
        'country': _selectedCountry,
        'gender': _selectedGender,
        'address': _addressController.text,
        'profileImageUrl': profileImageUrl,
        'hasCompletedProfile': true,
      });

      // Navigate to the MainScreen (Home Screen)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MainScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Complete Your Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Profile Picture with Edit Button
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : AssetImage('assets/images/default_profile.png') as ImageProvider,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(Icons.edit, color: Colors.white),
                        onPressed: _pickImage,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),

              // Full Name Field
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your full name';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Nickname Field
              TextFormField(
                controller: _nickNameController,
                decoration: InputDecoration(
                  labelText: 'Nickname',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your nickname';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Email Field
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Phone Number Field
              TextFormField(
                controller: _phoneNumberController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Country Dropdown
              DropdownButtonFormField<String>(
                value: _selectedCountry,
                decoration: InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                ),
                items: <String>['United States', 'Canada', 'Mexico', 'Other']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCountry = newValue!;
                  });
                },
              ),
              SizedBox(height: 20),

              // Gender Dropdown
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(),
                ),
                items: <String>['Female', 'Male', 'Other']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedGender = newValue!;
                  });
                },
              ),
              SizedBox(height: 20),

              // Address Field
              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your address';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveProfileData,
                  child: Text('Submit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}