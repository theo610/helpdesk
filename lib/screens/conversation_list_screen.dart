import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../repositories/chat_repository.dart';
import 'chat_screen.dart';
import 'mapScreen.dart';
import '../models/conversation.dart';

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({Key? key}) : super(key: key);

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final ChatRepository _chatRepository = ChatRepository();
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final Map<String, Map<String, dynamic>> _userCache = {};

  String _formatMessageTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return DateFormat('HH:mm').format(date);
    } else if (messageDate == yesterday) {
      return 'Yesterday ${DateFormat('HH:mm').format(date)}';
    } else {
      return DateFormat('MMM d, HH:mm').format(date);
    }
  }

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
            return Center(
              child: Text(
                'Error loading conversations\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No conversations yet\nStart a new conversation!',
                textAlign: TextAlign.center,
              ),
            );
          }

          final conversations = snapshot.data!;

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final otherUserId = conversation.participants.firstWhere((id) => id != currentUserId);

              return FutureBuilder<Map<String, dynamic>>(
                future: _userCache[otherUserId] != null
                    ? Future.value(_userCache[otherUserId])
                    : _chatRepository.getUserData(otherUserId).then((data) {
                  _userCache[otherUserId] = data;
                  return data;
                }),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return ListTile(
                      leading: const CircleAvatar(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      title: Container(
                        height: 16,
                        width: 100,
                        color: Colors.grey[300],
                      ),
                      subtitle: Container(
                        height: 12,
                        width: 150,
                        color: Colors.grey[200],
                      ),
                    );
                  }

                  if (!userSnapshot.hasData) {
                    return const ListTile(title: Text('User not found'));
                  }

                  final userData = userSnapshot.data!;
                  final userName = userData['nickName'] ?? userData['fullName'] ?? 'Unknown';
                  final profileImage = userData['profileImageUrl'];
                  final isActive = userData['isActive'] as bool? ?? false;
                  final isMe = conversation.lastMessageSenderId == currentUserId;
                  final lastMessage = conversation.lastMessage ?? 'No messages yet';

                  return ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundImage: profileImage != null ? NetworkImage(profileImage) : null,
                          child: profileImage == null
                              ? Text(userName.isNotEmpty ? userName[0] : '?')
                              : null,
                        ),
                        if (isActive)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(
                                  BorderSide(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ),
                      ],
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
                          _formatMessageTime(
                            conversation.lastMessageTime ?? conversation.createdAt ?? DateTime.now(),
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        if (conversation.getUnreadCount(currentUserId) > 0) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              conversation.getUnreadCount(currentUserId).toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
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
        child: const Icon(Icons.map),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MapScreen()),
          );
        },
        tooltip: 'View Nearby Users',
      ),
    );
  }

  void _searchUsers(BuildContext context) {
    showSearch(
      context: context,
      delegate: UserSearchDelegate(
        currentUserId: currentUserId,
        chatRepository: _chatRepository,
        userCache: _userCache,
      ),
    );
  }
}

class UserSearchDelegate extends SearchDelegate<String> {
  final String currentUserId;
  final ChatRepository chatRepository;
  final Map<String, Map<String, dynamic>> userCache;

  UserSearchDelegate({
    required this.currentUserId,
    required this.chatRepository,
    required this.userCache,
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
    if (query.isEmpty) {
      return const Center(child: Text('Enter a name to search'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('fullName', isGreaterThanOrEqualTo: query)
          .where('fullName', isLessThan: '${query}z')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
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
            final isActive = userData['isActive'] as bool? ?? false; // Fetch isActive status

            // Cache the user data
            userCache[user.id] = userData;

            return ListTile(
              leading: Stack(
                children: [
                  CircleAvatar(
                    backgroundImage: profileImage != null ? NetworkImage(profileImage) : null,
                    child: profileImage == null
                        ? Text(userName.isNotEmpty ? userName[0] : '?')
                        : null,
                  ),
                  if (isActive) // Show green dot if user is active
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(userName),
              subtitle: Text(userData['email'] ?? ''),
              onTap: () async {
                try {
                  final conversation = await chatRepository.getOrCreateConversation(
                    userId1: currentUserId,
                    userId2: user.id,
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
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to start conversation: $e')),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}