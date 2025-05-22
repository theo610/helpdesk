import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'admin_dashboard.dart';
import 'moderator_dashboard.dart';
import 'agent_dashboard.dart';
import 'employee_dashboard.dart';
import 'profile_screen.dart';
import 'conversation_list_screen.dart';

class RoleBasedMainScreen extends StatefulWidget {
  final String initialRole;

  const RoleBasedMainScreen({required this.initialRole, Key? key}) : super(key: key);

  @override
  _RoleBasedMainScreenState createState() => _RoleBasedMainScreenState();
}

class _RoleBasedMainScreenState extends State<RoleBasedMainScreen> {
  int _selectedIndex = 0;
  late String _userRole;
  bool _isLoading = false;

  List<Widget> _getScreens() {
    switch (_userRole) {
      case 'admin':
        return [
          AdminDashboard(),
          ConversationListScreen(),
          ProfileScreen(),
        ];
      case 'moderator':
        return [
          ModeratorDashboard(),
          ConversationListScreen(),
          ProfileScreen(),
        ];
      case 'agent':
        return [
          AgentDashboard(),
          ConversationListScreen(),
          ProfileScreen(),
        ];
      default: // employee
        return [
          EmployeeDashboard(),
          ConversationListScreen(),
          ProfileScreen(),
        ];
    }
  }

  List<BottomNavigationBarItem> _getBottomNavItems(BuildContext context) {
    return [
      BottomNavigationBarItem(
        icon: const Icon(Icons.dashboard),
        label: 'Dashboard',
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.message),
        label: 'Messages',
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.person),
        label: 'Profile',
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _userRole = widget.initialRole;
    _verifyUserRole();
  }

  Future<void> _verifyUserRole() async {
    setState(() => _isLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (userDoc.exists) {
        setState(() {
          _userRole = userDoc.data()?['role'] ?? widget.initialRole;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to verify user role: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final screens = _getScreens();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        children: List.generate(screens.length, (index) {
          return Offstage(
            offstage: _selectedIndex != index,
            child: screens[index],
          );
        }),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        selectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: _getBottomNavItems(context),
      ),
    );
  }
}