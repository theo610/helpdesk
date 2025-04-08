import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../repositories/chat_repository.dart';
import 'chat_screen.dart';
import '../models/conversation.dart';


class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({Key? key}) : super(key: key);

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final ChatRepository _chatRepository = ChatRepository();
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _searchUsers(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: _chatRepository.getUserConversations(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No conversations yet'));
          }

          final conversations = snapshot.data!;

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final otherUserId = conversation.participants
                  .firstWhere((id) => id != currentUserId);

              return FutureBuilder<Map<String, dynamic>>(
                future: _chatRepository.getUserData(otherUserId),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(title: Text('Loading...'));
                  }

                  final userData = userSnapshot.data!;
                  final userName = userData['nickName'] ?? userData['fullName'] ?? 'Unknown';
                  final profileImage = userData['profileImageUrl'];

                  final isMe = conversation.lastMessageSenderId == currentUserId;
                  final lastMessage = conversation.lastMessage ?? 'No messages yet';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: profileImage != null
                          ? NetworkImage(profileImage)
                          : null,
                      child: profileImage == null
                          ? Text(userName.isNotEmpty ? userName[0] : '?')
                          : null,
                    ),
                    title: Text(userName),
                    subtitle: Text(
                      isMe ? 'You: $lastMessage' : lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(
                            conversation.lastMessageTime ?? conversation.createdAt,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,                          ),
                        ),
                        const SizedBox(height: 4),
                        // Add unread indicator here if needed
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            conversationId: conversation.id,
                            otherUserId: otherUserId,
                            otherUserName: userName,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.message),
        onPressed: () => _searchUsers(context),
      ),
    );
  }

  void _searchUsers(BuildContext context) {
    // Implement user search functionality
    showSearch(
      context: context,
      delegate: UserSearchDelegate(
        currentUserId: currentUserId,
        chatRepository: _chatRepository,
      ),
    );
  }
}

class UserSearchDelegate extends SearchDelegate<String> {
  final String currentUserId;
  final ChatRepository chatRepository;

  UserSearchDelegate({
    required this.currentUserId,
    required this.chatRepository,
  });

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('fullName', isGreaterThanOrEqualTo: query)
          .where('fullName', isLessThan: '${query}z')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!.docs
            .where((doc) => doc.id != currentUserId)
            .toList();

        if (users.isEmpty) {
          return const Center(child: Text('No users found'));
        }

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final userData = user.data() as Map<String, dynamic>;
            final userName = userData['nickName'] ?? userData['fullName'] ?? 'Unknown';
            final profileImage = userData['profileImageUrl'];

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: profileImage != null
                    ? NetworkImage(profileImage)
                    : null,
                child: profileImage == null
                    ? Text(userName.isNotEmpty ? userName[0] : '?')
                    : null,
              ),
              title: Text(userName),
              subtitle: Text(userData['email'] ?? ''),
              onTap: () async {
                final conversation = await chatRepository.getOrCreateConversation(
                  currentUserId,
                  user.id,
                );
                close(context, '');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      conversationId: conversation.id,
                      otherUserId: user.id,
                      otherUserName: userName,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}