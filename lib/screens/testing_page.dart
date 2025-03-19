import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'loginScreen.dart'; // Import the LoginScreen

class TestingPage extends StatelessWidget {
  // Function to handle user logout
  Future<void> _logoutUser(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut(); // Sign out the user
      print('User logged out');

      // Navigate back to the LoginScreen after logout
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Testing Page'),
        actions: [
          // Logout Button in the AppBar
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => _logoutUser(context),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'this is a testing page',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _logoutUser(context),
              child: Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}