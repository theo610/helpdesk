import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'PendingRequestsScreen.dart';
import 'ProfileHistoryScreen.dart';
import 'admin_stats_screen.dart';
import 'ManagePlatformsScreen.dart';
import 'ManageUsersScreen.dart';

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
    const AdminStatsScreen(),
    const ManagePlatformsScreen(),
    const ManageUsersScreen(),
  ];

  // List of titles for the header
  final List<String> _screenTitles = [
    'Pending Requests',
    'Profile History',
    'Statistics',
    'Manage Platforms',
    'Manage Users',
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: NavigationDrawer(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              'Admin Menu',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.pending, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              'Pending Requests',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            selectedIcon: Icon(Icons.pending, color: Theme.of(context).colorScheme.primary),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.history, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              'Profile History',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            selectedIcon: Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.bar_chart, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              'Statistics',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            selectedIcon: Icon(Icons.bar_chart, color: Theme.of(context).colorScheme.primary),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.settings_applications, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              'Manage Platforms',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            selectedIcon: Icon(Icons.settings_applications, color: Theme.of(context).colorScheme.primary),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.people, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              'Manage Users',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            selectedIcon: Icon(Icons.people, color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
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
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _screens[_selectedIndex]),
            ],
          ),
        ),
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          Icons.add,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        onPressed: () {
          // Add new user logic
        },
        tooltip: 'Add New User',
      )
          : null,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    icon: Icon(
                      Icons.menu,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    tooltip: 'Open menu',
                  ),
                ),
                Flexible(
                  child: Text(
                    _screenTitles[_selectedIndex],
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onBackground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}