import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'dart:math';
import 'loginScreen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({Key? key}) : super(key: key);

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  double _buttonScale = 1.0;
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

  Future<void> _registerUser(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isLoading = true);
    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      print('User registered: ${userCredential.user!.email}');

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(-1.0, 0.0); // Slide from left
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            var slideTween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
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
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Registration failed. Please try again.';
      if (e.code == 'weak-password') {
        errorMessage = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'The account already exists for that email.';
      }
      _shakeController.forward(from: 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage, style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      print('Error: $e');
      _shakeController.forward(from: 0);
    } finally {
      setState(() => _isLoading = false);
    }
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
                label: 'Sign-up form, shake indicates invalid input',
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
                              'Create an Account',
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
                              'Enter your details to sign up',
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
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            label: 'Password input',
                            child: TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              style: GoogleFonts.poppins(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock, color: Theme.of(context).colorScheme.primary),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceVariant,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          GestureDetector(
                            onTapDown: (_) => setState(() => _buttonScale = 0.95),
                            onTapUp: (_) => setState(() => _buttonScale = 1.0),
                            onTapCancel: () => setState(() => _buttonScale = 1.0),
                            onTap: () => _registerUser(context),
                            child: Transform.scale(
                              scale: _buttonScale,
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : () => _registerUser(context),
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
                                    'Sign Up',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: TextButton(
                              onPressed: () {
                                Navigator.pushReplacement(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation, secondaryAnimation) =>
                                    const LoginScreen(),
                                    transitionsBuilder:
                                        (context, animation, secondaryAnimation, child) {
                                      const begin = Offset(-1.0, 0.0); // Slide from left
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
                                'Already have an account? Log In',
                                style: GoogleFonts.poppins(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 14,
                                ),
                              ),
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