import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime sentAt;
  final bool isRead;
  final List<String> participants;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.sentAt,
    this.isRead = false,
    required this.participants,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    try {
      return Message(
        id: map['id'] as String,
        conversationId: map['conversationId'] as String,
        senderId: map['senderId'] as String,
        content: map['content'] as String,
        sentAt: (map['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isRead: map['isRead'] as bool? ?? false,
        participants: List<String>.from(map['participants'] ?? []),
      );
    } catch (e) {
      print('Error parsing Message: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'content': content,
      'sentAt': Timestamp.fromDate(sentAt),
      'isRead': isRead,
      'participants': participants,
    };
  }
}