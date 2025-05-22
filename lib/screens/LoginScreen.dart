import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'dart:math';
import 'role_based_main_screen.dart';
import 'signup_screen.dart';
import 'profile_personalization_screen.dart';
import 'waiting_for_approval_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  double _loginButtonScale = 1.0;
  double _googleButtonScale = 1.0;
  bool _obscureText = true;
  bool _isLoading = false;
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  Future<Map<String, dynamic>> _getUserData(String uid, BuildContext context) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!userDoc.exists) {
        return {
          'hasCompletedProfile': false,
          'isApproved': false,
        };
      }

      return {
        'hasCompletedProfile': userDoc.data()?['hasCompletedProfile'] ?? false,
        'isApproved': userDoc.data()?['isApproved'] ?? false,
        'role': userDoc.data()?['role'] ?? 'employee',
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const WaitingForApprovalScreen(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => RoleBasedMainScreen(initialRole: role),
        ),
      );
    }
  }

  Future<void> _loginUser(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isLoading = true);
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
      _shakeController.forward(from: 0);
      _showErrorSnackbar(context, errorMessage);
    } catch (e) {
      _shakeController.forward(from: 0);
      _showErrorSnackbar(context, 'An unexpected error occurred. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    setState(() => _isLoading = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final uid = userCredential.user!.uid;

      _navigateBasedOnUserStatus(context, uid);
    } catch (e) {
      _shakeController.forward(from: 0);
      _showErrorSnackbar(context, 'Google login failed. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword(BuildContext context) async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _shakeController.forward(from: 0);
      _showErrorSnackbar(context, 'Please enter your email address');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSuccessSnackbar(context, 'Password reset email sent to $email');
    } on FirebaseAuthException catch (e) {
      _shakeController.forward(from: 0);
      _showErrorSnackbar(
        context,
        e.code == 'user-not-found' ? 'No user found with this email address.' : 'Failed to send password reset email.',
      );
    } catch (e) {
      _shakeController.forward(from: 0);
      _showErrorSnackbar(context, 'An error occurred. Please try again.');
    }
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccessSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: AnimationLimiter(
              child: Semantics(
                label: 'Login form, shake indicates invalid input',
                child: ShakeWidget(
                  controller: _shakeController,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: AnimationConfiguration.toStaggeredList(
                        duration: const Duration(milliseconds: 375),
                        childAnimationBuilder: (widget) => SlideAnimation(
                          verticalOffset: 50.0,
                          child: FadeInAnimation(child: widget),
                        ),
                        children: [
                          AnimatedOpacity(
                            opacity: 1.0,
                            duration: const Duration(milliseconds: 500),
                            child: Center(
                              child: Image.asset(
                                'assets/images/crmn_logo.png',
                                width: 200,
                                height: 200,
                                semanticLabel: 'App Logo',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              'Sign in to Your Account',
                              style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Enter your email and password to log in',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Semantics(
                            label: 'Email input',
                            child: TextFormField(
                              controller: _emailController,
                              style: GoogleFonts.poppins(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email, color: Theme.of(context).colorScheme.primary),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceVariant,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) => value?.isEmpty ?? true ? 'Please enter your email' : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            label: 'Password input',
                            child: TextFormField(
                              controller: _passwordController,
                              obscureText: _obscureText,
                              style: GoogleFonts.poppins(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock, color: Theme.of(context).colorScheme.primary),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureText ? Icons.visibility : Icons.visibility_off,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  onPressed: () => setState(() => _obscureText = !_obscureText),
                                ),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceVariant,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (value) => value?.isEmpty ?? true ? 'Please enter your password' : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _resetPassword(context),
                              child: Text(
                                'Forgot Password?',
                                style: GoogleFonts.poppins(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTapDown: (_) => setState(() => _loginButtonScale = 0.95),
                            onTapUp: (_) => setState(() => _loginButtonScale = 1.0),
                            onTapCancel: () => setState(() => _loginButtonScale = 1.0),
                            onTap: () => _loginUser(context),
                            child: Transform.scale(
                              scale: _loginButtonScale,
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : () => _loginUser(context),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.onPrimary,
                                    ),
                                  )
                                      : Text(
                                    'Log In',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  'OR',
                                  style: GoogleFonts.poppins(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTapDown: (_) => setState(() => _googleButtonScale = 0.95),
                            onTapUp: (_) => setState(() => _googleButtonScale = 1.0),
                            onTapCancel: () => setState(() => _googleButtonScale = 1.0),
                            onTap: () => _signInWithGoogle(context),
                            child: Transform.scale(
                              scale: _googleButtonScale,
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: Image.asset('assets/images/google_logo.png', width: 24),
                                  label: Text(
                                    'Continue with Google',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  ),
                                  onPressed: _isLoading ? null : () => _signInWithGoogle(context),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account? ",
                                  style: GoogleFonts.poppins(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontSize: 14,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation, secondaryAnimation) =>
                                        const SignUpScreen(),
                                        transitionsBuilder:
                                            (context, animation, secondaryAnimation, child) {
                                          const begin = Offset(1.0, 0.0); // Slide from right
                                          const end = Offset.zero;
                                          const curve = Curves.easeInOut;
                                          var slideTween =
                                          Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                          var fadeTween = Tween<double>(begin: 0.0, end: 1.0)
                                              .chain(CurveTween(curve: curve));
                                          return Stack(
                                            children: [
                                              SlideTransition(
                                                position: animation.drive(slideTween),
                                                child: FadeTransition(
                                                  opacity: animation.drive(fadeTween),
                                                  child: child,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                        transitionDuration: const Duration(milliseconds: 400),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'Sign Up',
                                    style: GoogleFonts.poppins(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ShakeWidget extends StatelessWidget {
  final AnimationController controller;
  final Widget child;

  const ShakeWidget({Key? key, required this.controller, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(10 * sin(controller.value * pi * 4), 0),
          child: child,
        );
      },
    );
  }
}