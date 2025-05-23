import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';

class ProfileHistoryScreen extends StatefulWidget {
  const ProfileHistoryScreen({Key? key}) : super(key: key);

  @override
  _ProfileHistoryScreenState createState() => _ProfileHistoryScreenState();
}

class _ProfileHistoryScreenState extends State<ProfileHistoryScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  List<Map<String, dynamic>> _initialProfiles = [];
  bool _isLoading = true;

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
    _animationController.forward();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      final deniedUsersSnapshot = await FirebaseFirestore.instance.collection('denied_users').get();

      final users = usersSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      final deniedUsers = deniedUsersSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        data['status'] = 'Denied';
        return data;
      }).toList();

      _initialProfiles = [...users, ...deniedUsers]..sort((a, b) {
        final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        return bTime.compareTo(aTime); // Sort by createdAt, newest first
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading initial data: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _isLoading
                ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            )
                : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile Request History',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _combineUserStreams(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Error loading profile history: ${snapshot.error}',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _loadInitialData(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                                child: Text(
                                  'Retry',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final profiles = snapshot.data ?? _initialProfiles;
                      if (profiles.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history,
                                size: 48,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No profile history available.',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return AnimationLimiter(
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: profiles.length,
                          itemBuilder: (context, index) {
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: SlideAnimation(
                                verticalOffset: 50.0,
                                child: FadeInAnimation(
                                  child: _buildProfileCard(profiles[index]),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
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
          await _loadInitialData();
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

  Widget _buildProfileCard(Map<String, dynamic> profile) {
    final status = profile['status'] ?? 'Pending';
    final isApproved = profile['isApproved'] ?? false;
    final displayStatus = status == 'Denied'
        ? 'Denied'
        : isApproved
        ? 'Approved'
        : 'Pending';

    Color statusColor;
    switch (displayStatus) {
      case 'Approved':
        statusColor = Theme.of(context).colorScheme.primary;
        break;
      case 'Denied':
        statusColor = Theme.of(context).colorScheme.error;
        break;
      case 'Pending':
      default:
        statusColor = Colors.orange;
        break;
    }

    final createdAt = (profile['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final formattedDate = DateFormat('MMM dd, yyyy • HH:mm').format(createdAt.toLocal());

    return Semantics(
      label: 'Profile card, ${profile['email'] ?? 'No Email'}, Status: $displayStatus',
      child: Card(
        color: Theme.of(context).colorScheme.surface,
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile['email'] ?? 'No Email',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Role: ${profile['role'] ?? 'N/A'}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Full Name: ${profile['fullName'] ?? 'N/A'}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Nickname: ${profile['nickName'] ?? 'N/A'}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (profile['role'] == 'agent' || profile['role'] == 'moderator')
                    Text(
                      'Platform: ${profile['platform'] ?? 'N/A'}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    'Created At: $formattedDate',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Text(
                  displayStatus,
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _combineUserStreams() {
    final usersStream = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList());

    final deniedUsersStream = FirebaseFirestore.instance
        .collection('denied_users')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      data['status'] = 'Denied';
      return data;
    }).toList());

    return usersStream.asyncMap((users) async {
      final deniedUsers = await deniedUsersStream.first;
      return [...users, ...deniedUsers]..sort((a, b) {
        final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        return bTime.compareTo(aTime); // Sort by createdAt, newest first
      });
    });
  }
}