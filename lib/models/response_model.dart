import 'package:cloud_firestore/cloud_firestore.dart';

class Response {
  final String id;
  final String message;
  final String createdBy;
  final DateTime createdAt;
  final bool isInternal;

  Response({
    required this.id,
    required this.message,
    required this.createdBy,
    required this.createdAt,
    required this.isInternal,
  });

  factory Response.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return Response(
      id: doc.id,
      message: data?['message'] as String? ?? '',
      createdBy: data?['createdBy'] as String? ?? '',
      createdAt: (data?['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isInternal: data?['isInternal'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'message': message,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'isInternal': isInternal,
    };
  }
}