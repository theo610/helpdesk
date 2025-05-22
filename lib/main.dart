import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/loginScreen.dart';
import 'screens/signup_screen.dart';
import 'screens/profile_personalization_screen.dart';
import 'screens/role_based_main_screen.dart';
import 'screens/waiting_for_approval_screen.dart';
import 'screens/splashScreen.dart';
import 'screens/agent_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
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
    _updateUserActivity(true);
  }

  void _initializeAuthListener() {
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null && _lastActiveUserId != null) {
        await _forceUpdateUserActivity(_lastActiveUserId!, false);
      }
      _lastActiveUserId = user?.uid;
      if (user != null) {
        await _updateUserActivity(true);
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _updateUserActivity(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _updateUserActivity(true);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _updateUserActivity(false);
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
      title: 'Ticketing App',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6200EA),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
        cardTheme: CardTheme(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        scaffoldBackgroundColor: Theme.of(context).colorScheme.background,
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          labelStyle: GoogleFonts.poppins(),
          hintStyle: GoogleFonts.poppins(color: Theme.of(context).hintColor),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6200EA),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
        cardTheme: CardTheme(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        scaffoldBackgroundColor: Theme.of(context).colorScheme.background,
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          labelStyle: GoogleFonts.poppins(),
          hintStyle: GoogleFonts.poppins(color: Theme.of(context).hintColor),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => SplashScreen(), // Removed const
        '/login': (context) => LoginScreen(), // Removed const
        '/signup': (context) => SignUpScreen(), // Removed const
        '/waiting': (context) => const WaitingForApprovalScreen(),
        '/agent_dashboard': (context) => const AgentDashboard(),
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
        return null;
      },
    );
  }
}