import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'dart:io';
import 'dart:math';
import 'role_based_main_screen.dart';
import 'waiting_for_approval_screen.dart';
import 'otp_screen.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

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

class _ProfilePersonalizationScreenState extends State<ProfilePersonalizationScreen> with SingleTickerProviderStateMixin {
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
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    print('ProfilePersonalizationScreen initState: UID=${widget.uid}, isAdmin=${widget.isAdmin}');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != widget.uid) {
      print('Authentication error: No user or UID mismatch');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Authentication error. Please sign in again.',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
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
    _animationController.forward();
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
        SnackBar(
          content: Text(
            'Failed to load platforms: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
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
        SnackBar(
          content: Text(
            'Error uploading image: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
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

  Future<void> _sendEmailOTP(String otp) async {
    final gmailAddress = dotenv.env['GMAIL_ADDRESS'];
    final appPassword = dotenv.env['GMAIL_APP_PASSWORD'];

    if (gmailAddress == null || appPassword == null) {
      throw Exception('Missing Gmail credentials in .env file');
    }

    final smtpServer = gmail(gmailAddress, appPassword);
    final message = Message()
      ..from = Address(gmailAddress, 'Your App')
      ..recipients.add(_emailController.text)
      ..subject = 'Your OTP Code'
      ..text = 'Your verification code is $otp. It expires in 5 minutes.';

    try {
      await send(message, smtpServer);
    } catch (e) {
      throw Exception('Failed to send email: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    print('Preparing to save profile for UID=${widget.uid}');
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

      final phoneNumber = _phoneNumberController.text.trim();

      final otp = Random().nextInt(999999).toString().padLeft(6, '0');
      final expiry = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;

      await _sendEmailOTP(otp);

      await firestore.collection('otp_verifications').doc(widget.uid).set({
        'otp': otp,
        'expiry': expiry,
        'verified': false,
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OTPScreen(
            userId: widget.uid,
            phoneNumber: phoneNumber,
            onVerified: () async {
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
                'is2FAVerified': true,
                'shareLocation': _shareLocation,
                if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
                'lastUpdated': FieldValue.serverTimestamp(),
                'createdAt': FieldValue.serverTimestamp(),
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
                SnackBar(
                  content: Text(
                    'Profile submitted for admin approval!',
                    style: GoogleFonts.poppins(),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              );

              print('Navigating to WaitingForApprovalScreen');
              Navigator.pushReplacementNamed(context, '/waiting');
            },
          ),
        ),
      );
    } catch (e) {
      print('Error initiating 2FA: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('Building ProfilePersonalizationScreen for UID=${widget.uid}');
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
          child: _isLoading
              ? Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          )
              : FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: AnimationLimiter(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: AnimationConfiguration.toStaggeredList(
                            duration: const Duration(milliseconds: 375),
                            childAnimationBuilder: (widget) => SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(
                                child: widget,
                              ),
                            ),
                            children: [
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  CircleAvatar(
                                    radius: 60,
                                    backgroundImage: _profileImage != null
                                        ? FileImage(_profileImage!)
                                        : const AssetImage('assets/default_profile.png') as ImageProvider,
                                    backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.camera_alt, size: 20, color: Theme.of(context).colorScheme.onPrimary),
                                      onPressed: _pickImage,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildTextField('Full Name', _fullNameController, Icons.person),
                              const SizedBox(height: 16),
                              _buildTextField('Nickname', _nickNameController, Icons.face),
                              const SizedBox(height: 16),
                              _buildTextField('Email', _emailController, Icons.email, keyboardType: TextInputType.emailAddress),
                              const SizedBox(height: 16),
                              _buildTextField('Phone Number', _phoneNumberController, Icons.phone, keyboardType: TextInputType.phone),
                              const SizedBox(height: 16),
                              _buildCountryDropdown(),
                              const SizedBox(height: 16),
                              _buildGenderDropdown(),
                              const SizedBox(height: 16),
                              if (!widget.isAdmin) _buildRoleDropdown(),
                              if (!widget.isAdmin) const SizedBox(height: 16),
                              if (widget.isAdmin)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Theme.of(context).colorScheme.primary),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.verified_user, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Admin Account',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (widget.isAdmin) const SizedBox(height: 16),
                              if (_selectedRole == 'agent' || _selectedRole == 'moderator')
                                _buildPlatformDropdown(),
                              if (_selectedRole == 'agent' || _selectedRole == 'moderator')
                                const SizedBox(height: 16),
                              _buildTextField('Address', _addressController, Icons.home, maxLines: 2),
                              const SizedBox(height: 16),
                              SwitchListTile(
                                title: Text(
                                  'Share Location',
                                  style: GoogleFonts.poppins(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Text(
                                  'Allow others to see your location on the map',
                                  style: GoogleFonts.poppins(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                value: _shareLocation,
                                onChanged: (value) {
                                  setState(() {
                                    _shareLocation = value;
                                  });
                                },
                                secondary: Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                              ),
                              const SizedBox(height: 24),
                              _buildSubmitButton(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            'Complete Your Profile',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onBackground,
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {TextInputType? keyboardType, int maxLines = 1}) {
    return Semantics(
      label: label,
      child: TextFormField(
        controller: controller,
        style: GoogleFonts.poppins(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
          contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter your ${label.toLowerCase()}';
          }
          if (label == 'Email' && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
            return 'Please enter a valid email';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildCountryDropdown() {
    return Semantics(
      label: 'Country selection',
      child: DropdownButtonFormField<String>(
        value: _selectedCountry,
        decoration: InputDecoration(
          labelText: 'Country',
          labelStyle: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          prefixIcon: Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: GoogleFonts.poppins(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
        dropdownColor: Theme.of(context).colorScheme.surface,
        icon: Icon(
          Icons.arrow_drop_down,
          color: Theme.of(context).colorScheme.primary,
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
    );
  }

  Widget _buildGenderDropdown() {
    return Semantics(
      label: 'Gender selection',
      child: DropdownButtonFormField<String>(
        value: _selectedGender,
        decoration: InputDecoration(
          labelText: 'Gender',
          labelStyle: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          prefixIcon: Icon(Icons.transgender, color: Theme.of(context).colorScheme.primary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: GoogleFonts.poppins(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
        dropdownColor: Theme.of(context).colorScheme.surface,
        icon: Icon(
          Icons.arrow_drop_down,
          color: Theme.of(context).colorScheme.primary,
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
    );
  }

  Widget _buildRoleDropdown() {
    return Semantics(
      label: 'User role selection',
      child: DropdownButtonFormField<String>(
        value: _selectedRole,
        decoration: InputDecoration(
          labelText: 'User Role',
          labelStyle: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          prefixIcon: Icon(Icons.work, color: Theme.of(context).colorScheme.primary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: GoogleFonts.poppins(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
        dropdownColor: Theme.of(context).colorScheme.surface,
        icon: Icon(
          Icons.arrow_drop_down,
          color: Theme.of(context).colorScheme.primary,
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
    );
  }

  Widget _buildPlatformDropdown() {
    return Semantics(
      label: 'Platform selection',
      child: DropdownButtonFormField<String>(
        value: _selectedPlatform,
        decoration: InputDecoration(
          labelText: 'Platform',
          labelStyle: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          prefixIcon: Icon(Icons.build, color: Theme.of(context).colorScheme.primary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: GoogleFonts.poppins(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
        dropdownColor: Theme.of(context).colorScheme.surface,
        icon: Icon(
          Icons.arrow_drop_down,
          color: Theme.of(context).colorScheme.primary,
        ),
        hint: Text(
          'Select Platform',
          style: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
          ),
        ),
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
    );
  }

  Widget _buildSubmitButton() {
    return Semantics(
      label: 'Submit profile',
      child: SizedBox(
        width: 150,
        height: 50,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _saveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            shadowColor: Colors.black.withOpacity(0.2),
          ),
          child: _isLoading
              ? CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.onPrimary,
            ),
          )
              : Text(
            'Submit',
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}