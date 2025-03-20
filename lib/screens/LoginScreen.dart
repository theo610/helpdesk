import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // For Firestore
import 'package:shared_preferences/shared_preferences.dart'; // For SharedPreferences
import 'main_screen.dart'; // Import the MainScreen
import 'signup_screen.dart'; // Import the Sign-Up Screen
import 'profile_personalization_screen.dart'; // Import the Profile Personalization Screen

class LoginScreen extends StatelessWidget {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Function to check if the user has completed profile personalization (Firestore)
  Future<bool> hasUserCompletedProfileFirestore(String uid) async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (userDoc.exists) {
      return userDoc.data()!['hasCompletedProfile'] ?? false;
    }
    return false; // Assume profile is not completed if the document doesn't exist
  }

  // Function to check if the user has completed profile personalization (SharedPreferences)
  Future<bool> hasUserCompletedProfileSharedPreferences(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$uid-hasCompletedProfile') ?? false;
  }

  // Function to handle user login
  Future<void> _loginUser(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      try {
        // Sign in with email and password
        UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Get the user's UID
        final uid = userCredential.user!.uid;

        // Check if the user has completed profile personalization
        final hasCompletedProfile = await hasUserCompletedProfileFirestore(uid); // Use Firestore
        // final hasCompletedProfile = await hasUserCompletedProfileSharedPreferences(uid); // Use SharedPreferences

        // Navigate based on profile completion status
        if (hasCompletedProfile) {
          // Navigate to the MainScreen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MainScreen()),
          );
        } else {
          // Navigate to the Profile Personalization Screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProfilePersonalizationScreen(uid: uid)),
          );
        }
      } on FirebaseAuthException catch (e) {
        // Handle login errors
        String errorMessage = 'Login failed. Please try again.';
        if (e.code == 'user-not-found') {
          errorMessage = 'No user found for that email.';
        } else if (e.code == 'wrong-password') {
          errorMessage = 'Wrong password provided.';
        }

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      } catch (e) {
        // Handle other errors
        print('Error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred. Please try again.')),
        );
      }
    }
  }

  // Function to handle Google Sign-In
  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        // User canceled the sign-in process
        return;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the credential
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      // Get the user's UID
      final uid = userCredential.user!.uid;

      // Check if the user has completed profile personalization
      final hasCompletedProfile = await hasUserCompletedProfileFirestore(uid); // Use Firestore
      // final hasCompletedProfile = await hasUserCompletedProfileSharedPreferences(uid); // Use SharedPreferences

      // Navigate based on profile completion status
      if (hasCompletedProfile) {
        // Navigate to the MainScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainScreen()),
        );
      } else {
        // Navigate to the Profile Personalization Screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ProfilePersonalizationScreen(uid: uid)),
        );
      }
    } catch (e) {
      print('Error during Google login: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google login failed. Please try again.')),
      );
    }
  }

  // Function to handle forgot password
  Future<void> _resetPassword(BuildContext context) async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter your email address')),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email')),
      );
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Failed to send password reset email.';
      if (e.code == 'user-not-found') {
        errorMessage = 'No user found with this email address.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } catch (e) {
      print('Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Image.asset('assets/images/crmn_logo.png', width: 200, height: 200),
                SizedBox(height: 10),

                // Title
                Text(
                  'Sign in to your Account',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),

                // Subtitle
                Text(
                  'Enter your email and password to log in',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: 20),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),

                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 10),

                // Forgot Password Link
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _resetPassword(context),
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _loginUser(context),
                    child: Text('Log In'),
                  ),
                ),
                SizedBox(height: 20),

                // Or Divider
                Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('Or'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                SizedBox(height: 20),

                // Continue with Google Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _signInWithGoogle(context),
                    icon: Image.asset('assets/images/google_logo.png', width: 24),
                    label: Text('Continue with Google'),
                  ),
                ),
                SizedBox(height: 20),

                // Sign Up Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account?"),
                    TextButton(
                      onPressed: () {
                        // Navigate to the Sign-Up Screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SignUpScreen()),
                        );
                      },
                      child: Text(
                        'Sign Up',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}