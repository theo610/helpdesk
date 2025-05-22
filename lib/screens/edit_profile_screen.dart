import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

class EditProfileScreen extends StatefulWidget {
  final String userId;

  const EditProfileScreen({required this.userId, Key? key}) : super(key: key);

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> with SingleTickerProviderStateMixin {
  String _selectedRole = 'employee';
  String? _selectedPlatform;
  List<String> _platforms = [];
  bool _isLoading = false;
  Map<String, dynamic>? _userData;
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
    _fetchUserData();
    _loadPlatforms();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    try {
      setState(() => _isLoading = true);
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data();
          _selectedRole = _userData!['role'] ?? 'employee';
          _selectedPlatform = _userData!['platform'];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'User data not found',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error fetching user data: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _loadPlatforms() async {
    try {
      final platformsSnapshot = await FirebaseFirestore.instance.collection('platforms').get();
      setState(() {
        _platforms = platformsSnapshot.docs
            .map((doc) => doc.data()['designation'] as String)
            .toList();
      });
    } catch (e) {
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

  Future<void> _saveProfile() async {
    try {
      setState(() => _isLoading = true);
      final updateData = {
        'role': _selectedRole,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (_selectedRole == 'agent' || _selectedRole == 'moderator') {
        if (_selectedPlatform == null || _selectedPlatform!.isEmpty) {
          throw Exception('Platform is required for agent or moderator roles');
        }
        updateData['platform'] = _selectedPlatform!;
      } else if (_selectedRole == 'employee') {
        updateData['platform'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(updateData);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile updated successfully!',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error updating profile: $e',
            style: GoogleFonts.poppins(),
          ),
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
          child: _isLoading || _userData == null
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
                            CircleAvatar(
                              radius: 60,
                              backgroundImage: _userData!['profileImageUrl'] != null
                                  ? NetworkImage(_userData!['profileImageUrl'])
                                  : const AssetImage('assets/default_profile.png') as ImageProvider,
                              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                            ),
                            const SizedBox(height: 24),
                            _buildTextField('Full Name', _userData!['fullName'], Icons.person),
                            const SizedBox(height: 16),
                            _buildTextField('Nickname', _userData!['nickName'], Icons.face),
                            const SizedBox(height: 16),
                            _buildTextField('Email', _userData!['email'], Icons.email),
                            const SizedBox(height: 16),
                            _buildTextField('Phone Number', _userData!['phoneNumber'], Icons.phone),
                            const SizedBox(height: 16),
                            _buildTextField('Address', _userData!['address'], Icons.home, maxLines: 2),
                            const SizedBox(height: 16),
                            _buildTextField('Country', _userData!['country'], Icons.location_on),
                            const SizedBox(height: 16),
                            _buildTextField('Gender', _userData!['gender'], Icons.transgender),
                            const SizedBox(height: 16),
                            _buildRoleDropdown(),
                            const SizedBox(height: 16),
                            if (_selectedRole == 'agent' || _selectedRole == 'moderator')
                              _buildPlatformDropdown(),
                            const SizedBox(height: 24),
                            _buildSaveButton(),
                          ],
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
            'Edit Profile',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onBackground,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String? text, IconData icon, {int maxLines = 1}) {
    return Semantics(
      label: label,
      child: TextField(
        controller: TextEditingController(text: text ?? ''),
        readOnly: true,
        style: GoogleFonts.poppins(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
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

  Widget _buildSaveButton() {
    return Semantics(
      label: 'Save profile changes',
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
            'Save',
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