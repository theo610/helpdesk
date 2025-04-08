import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/conversation.dart';
import '../models/message.dart';

class ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create or get existing conversation between users
  Future<Conversation> getOrCreateConversation(String userId1, String userId2) async {
    final participants = [userId1, userId2]..sort();

    try {
      final query = await _firestore
          .collection('conversations')
          .where('participants', isEqualTo: participants)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return Conversation.fromMap({
          'id': query.docs.first.id,
          ...query.docs.first.data(),
        });
      }

      final docRef = await _firestore.collection('conversations').add({
        'participants': participants,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return Conversation(
        id: docRef.id,
        participants: participants,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to get/create conversation: $e');
    }
  }

  // Send a message
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    required List<String> participants,
  }) async {
    try {
      final batch = _firestore.batch();

      // Add the message
      final messageRef = _firestore.collection('messages').doc();
      batch.set(messageRef, {
        'id': messageRef.id,
        'conversationId': conversationId,
        'senderId': senderId,
        'content': content,
        'sentAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'participants': participants,
      });

      // Update conversation last message
      final conversationRef = _firestore.collection('conversations').doc(conversationId);
      batch.update(conversationRef, {
        'lastMessage': content,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
      });

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // Stream of messages for a conversation
  Stream<List<Message>> getMessagesStream(String conversationId) {
    return _firestore
        .collection('messages')
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Message.fromMap({'id': doc.id, ...doc.data()}))
        .toList());
  }

  // Stream of user conversations
  Stream<List<Conversation>> getUserConversations(String userId) {
    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Conversation.fromMap({'id': doc.id, ...doc.data()}))
        .toList());
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String conversationId, String userId) async {
    try {
      final query = await _firestore
          .collection('messages')
          .where('conversationId', isEqualTo: conversationId)
          .where('senderId', isNotEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in query.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to mark messages as read: $e');
    }
  }

  // Get user data
  Future<Map<String, dynamic>> getUserData(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.data() ?? {};
  }
}