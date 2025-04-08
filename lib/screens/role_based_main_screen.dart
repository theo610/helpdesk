import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_dashboard.dart';
import 'moderator_dashboard.dart';
import 'agent_dashboard.dart';
import 'employee_dashboard.dart';
import 'profile_screen.dart';
import 'conversation_list_screen.dart';

class RoleBasedMainScreen extends StatefulWidget {
  final String initialRole;

  const RoleBasedMainScreen({required this.initialRole});

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
          ProfileScreen()
        ];
      case 'moderator':
        return [
          ModeratorDashboard(),
          ConversationListScreen(),
          ProfileScreen()
        ];
      case 'agent':
        return [
          AgentDashboard(),
          ConversationListScreen(),
          ProfileScreen()
        ];
      default: // employee
        return [
          EmployeeDashboard(),
          ConversationListScreen(),
          ProfileScreen()
        ];
    }
  }

  List<BottomNavigationBarItem> _getBottomNavItems() {
    return [
      const BottomNavigationBarItem(
        icon: Icon(Icons.dashboard),
        label: 'Dashboard',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.message),
        label: 'Messages',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.person),
        label: 'Profile',
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
        SnackBar(content: Text('Failed to verify user role: $e')),
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _getScreens(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: _getBottomNavItems(),
      ),
    );
  }
}