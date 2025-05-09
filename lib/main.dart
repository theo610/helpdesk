import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/loginScreen.dart';
import 'screens/signup_screen.dart';
import 'screens/profile_personalization_screen.dart';
import 'screens/role_based_main_screen.dart';
import 'screens/waiting_for_approval_screen.dart';
import 'screens/splashScreen.dart'; // Import the splash screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<User?>? _authStateSubscription;
  String? _lastActiveUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAuthListener();
    _updateUserActivity(true); // App started
  }

  void _initializeAuthListener() {
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null && _lastActiveUserId != null) {
        // User logged out - mark inactive immediately
        await _forceUpdateUserActivity(_lastActiveUserId!, false);
      }
      _lastActiveUserId = user?.uid;
      if (user != null) {
        // User logged in - mark active
        await _updateUserActivity(true);
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _updateUserActivity(false); // App closing
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _updateUserActivity(true); // App came to foreground
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _updateUserActivity(false); // App went to background
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _updateUserActivity(bool isActive) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _lastActiveUserId = user.uid;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'isActive': isActive,
          'lastActive': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error updating user activity: $e');
    }
  }

  Future<void> _forceUpdateUserActivity(String userId, bool isActive) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'isActive': isActive,
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error force updating user activity: $e');
      // If update fails (document might not exist), try set with merge
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({
        'isActive': isActive,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/splash', // Set splash screen as initial route
      routes: {
        '/splash': (context) => SplashScreen(), // Remove 'const' here
        '/login': (context) => LoginScreen(),
        '/signup': (context) => SignUpScreen(),
        '/waiting': (context) => WaitingForApprovalScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/profile') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ProfilePersonalizationScreen(
              uid: args['uid'],
              isAdmin: args['isAdmin'],
            ),
          );
        }
        if (settings.name == '/main') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => RoleBasedMainScreen(
              initialRole: args['role'],
            ),
          );
        }
        return null; // Let Flutter handle unknown routes
      },
    );
  }
}