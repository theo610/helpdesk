import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';

class ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = Uuid();

  Future<Conversation> getOrCreateConversation({
    required String userId1,
    required String userId2,
  }) async {
    final participants = [userId1, userId2]..sort();
    String conversationId;

    try {
      // Check if a conversation already exists between these users
      final existingConversations = await _firestore
          .collection('conversations')
          .where('participants', arrayContains: userId1)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? directConversation;
      for (var doc in existingConversations.docs) {
        if ((doc['participants'] as List).contains(userId2)) {
          directConversation = doc;
          break;
        }
      }

      if (directConversation != null) {
        conversationId = directConversation.id;
        print('Found existing conversation: $conversationId');
        return Conversation.fromMap({
          'id': directConversation.id,
          ...directConversation.data(),
        });
      }

      // Generate a unique ID for the conversation
      final uniqueId = _uuid.v4().substring(0, 8);
      conversationId = '${participants.join('_')}_$uniqueId';
      print('Attempting to create conversation: $conversationId, participants: $participants');

      final conversationRef = _firestore.collection('conversations').doc(conversationId);
      final snapshot = await conversationRef.get();

      if (!snapshot.exists) {
        print('Conversation does not exist, creating new conversation...');
        await conversationRef.set({
          'participants': participants,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': null,
          'lastMessageTime': null,
          'lastMessageSenderId': null,
          'unreadCounts': {
            userId1: 0,
            userId2: 0,
          },
        });
      }

      final doc = await conversationRef.get();
      print('Conversation retrieved/created successfully: $conversationId');
      return Conversation.fromMap({
        'id': doc.id,
        ...doc.data()!,
      });
    } catch (e) {
      print('Error in getOrCreateConversation: $e');
      throw Exception('Failed to get/create conversation: $e');
    }
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    required List<String> participants,
  }) async {
    try {
      final batch = _firestore.batch();

      final messageRef = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc();
      batch.set(messageRef, {
        'id': messageRef.id,
        'conversationId': conversationId,
        'senderId': senderId,
        'content': content,
        'sentAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'participants': participants,
      });

      final conversationRef = _firestore.collection('conversations').doc(conversationId);
      final updates = {
        'lastMessage': content,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
      };
      for (final userId in participants) {
        if (userId != senderId) {
          updates['unreadCounts.$userId'] = FieldValue.increment(1);
        } else {
          updates['unreadCounts.$userId'] = 0;
        }
      }
      batch.update(conversationRef, updates);

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Stream<List<Message>> getMessagesStream(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Message.fromMap({'id': doc.id, ...doc.data()}))
        .toList());
  }

  Stream<List<Conversation>> getUserConversations(String userId) {
    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Conversation.fromMap({
      'id': doc.id,
      ...doc.data(),
    }))
        .toList());
  }

  Future<void> markMessagesAsRead(String conversationId, String userId) async {
    try {
      final batch = _firestore.batch();

      final query = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isNotEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();
      for (final doc in query.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      final conversationRef = _firestore.collection('conversations').doc(conversationId);
      batch.update(conversationRef, {
        'unreadCounts.$userId': 0,
      });

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to mark messages as read: $e');
    }
  }

  Future<Map<String, dynamic>> getUserData(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.data() ?? {};
  }

  Future<Map<String, dynamic>> getTicketDetails(String ticketId) async {
    try {
      final ticketDoc = await _firestore.collection('tickets').doc(ticketId).get();
      if (!ticketDoc.exists) {
        throw Exception('Ticket not found');
      }
      return ticketDoc.data() ?? {};
    } catch (e) {
      throw Exception('Failed to fetch ticket details: $e');
    }
  }
}