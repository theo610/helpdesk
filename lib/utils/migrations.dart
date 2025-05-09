import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreMigrations {
  static Future<void> migrateUserLocationSharing() async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      for (var userDoc in usersSnapshot.docs) {
        await userDoc.reference.update({
          'shareLocation': true, // Default to true for existing users, or false if preferred
        });
      }
      print('Migration completed: Added shareLocation field to all users.');
    } catch (e) {
      print('Error during migration: $e');
      rethrow; // Rethrow the error so it can be handled by the caller if needed
    }
  }
}