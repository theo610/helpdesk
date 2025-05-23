import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({required this.userId, super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _userData;
  bool _isLoading = false;
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
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'User data not found',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error fetching user data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error fetching user data: $e',
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
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
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: AnimationConfiguration.toStaggeredList(
                          duration: const Duration(milliseconds: 375),
                          childAnimationBuilder: (widget) => SlideAnimation(
                            verticalOffset: 50.0,
                            child: FadeInAnimation(child: widget),
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
                            _buildTextField('Role', _userData!['role'] ?? 'employee', Icons.work),
                            if (_userData!['role'] == 'agent' || _userData!['role'] == 'moderator') ...[
                              const SizedBox(height: 16),
                              _buildTextField('Platform', _userData!['platform'], Icons.build),
                            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'User Profile',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onBackground,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Theme.of(context).colorScheme.primary),
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
        controller: TextEditingController(text: text ?? 'Not provided'),
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
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }
}