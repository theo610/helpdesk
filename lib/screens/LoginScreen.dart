import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'role_based_main_screen.dart';
import 'signup_screen.dart';
import 'profile_personalization_screen.dart';
import 'waiting_for_approval_screen.dart';

class LoginScreen extends StatelessWidget {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Future<Map<String, dynamic>> _getUserData(String uid, BuildContext context) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        return {
          'hasCompletedProfile': false,
          'isApproved': false,
        };
      }

      return {
        'hasCompletedProfile': userDoc.data()?['hasCompletedProfile'] ?? false,
        'isApproved': userDoc.data()?['isApproved'] ?? false,
        'role': userDoc.data()?['role'] ?? 'employee', // Fallback role for navigation
      };
    } catch (e) {
      print('Error fetching user data: $e');
      _showErrorSnackbar(context, 'Error fetching user data: $e');
      return {
        'hasCompletedProfile': false,
        'isApproved': false,
      };
    }
  }

  void _navigateBasedOnUserStatus(BuildContext context, String uid) async {
    final userData = await _getUserData(uid, context);
    final hasCompletedProfile = userData['hasCompletedProfile'];
    final isApproved = userData['isApproved'];
    final role = userData['role'] ?? 'employee';

    if (!hasCompletedProfile) {
      // If the user hasn't completed their profile, send them to the personalization screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ProfilePersonalizationScreen(
            uid: uid,
            isAdmin: role == 'admin',
          ),
        ),
      );
    } else if (!isApproved) {
      // If the profile is not approved, send them to the waiting screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WaitingForApprovalScreen(),
        ),
      );
    } else {
      // If the profile is approved, send them to the dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => RoleBasedMainScreen(initialRole: role),
        ),
      );
    }
  }

  Future<void> _loginUser(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      _navigateBasedOnUserStatus(context, userCredential.user!.uid);
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found for that email.';
          break;
        case 'wrong-password':
          errorMessage = 'Wrong password provided.';
          break;
        case 'user-disabled':
          errorMessage = 'Account disabled. Contact administrator.';
          break;
        default:
          errorMessage = 'Login failed. Please try again.';
      }
      _showErrorSnackbar(context, errorMessage);
    } catch (e) {
      _showErrorSnackbar(context, 'An unexpected error occurred. Please try again.');
    }
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final uid = userCredential.user!.uid;

      _navigateBasedOnUserStatus(context, uid);
    } catch (e) {
      _showErrorSnackbar(context, 'Google login failed. Please try again.');
    }
  }

  Future<void> _resetPassword(BuildContext context) async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showErrorSnackbar(context, 'Please enter your email address');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSuccessSnackbar(context, 'Password reset email sent to $email');
    } on FirebaseAuthException catch (e) {
      _showErrorSnackbar(
        context,
        e.code == 'user-not-found'
            ? 'No user found with this email address.'
            : 'Failed to send password reset email.',
      );
    } catch (e) {
      _showErrorSnackbar(context, 'An error occurred. Please try again.');
    }
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
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
                Image.asset('assets/images/crmn_logo.png', width: 200, height: 200),
                const SizedBox(height: 16),
                Text(
                  'Sign in to your Account',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your email and password to log in',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => value?.isEmpty ?? true ? 'Please enter your email' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Please enter your password' : null,
                ),
                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _resetPassword(context),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => _loginUser(context),
                    child: const Text('LOG IN'),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'OR',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    icon: Image.asset('assets/images/google_logo.png', width: 24),
                    label: const Text('Continue with Google'),
                    onPressed: () => _signInWithGoogle(context),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account?"),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SignUpScreen()),
                        );
                      },
                      child: const Text(
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