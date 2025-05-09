import 'package:flutter/material.dart';
import 'PendingRequestsScreen.dart';
import 'ProfileHistoryScreen.dart';
import 'statistics_screen.dart';
import 'ManagePlatformsScreen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  // List of screens to switch between
  final List<Widget> _screens = [
    const PendingRequestsScreen(),
    const ProfileHistoryScreen(),
    const StatisticsScreen(),
    const ManagePlatformsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to admin settings
            },
          ),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Text(
              'Admin Menu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
              ),
            ),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.pending),
            label: const Text('Pending Requests'),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.history),
            label: const Text('Profile History'),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.bar_chart),
            label: const Text('Statistics'),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.settings_applications),
            label: const Text('Manage Platforms'),
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          // Add new user
        },
      )
          : null, // Only show FAB on Pending Requests screen
    );
  }
}