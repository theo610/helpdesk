import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileHistoryScreen extends StatelessWidget {
  const ProfileHistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile Request History',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _combineUserStreams(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final profiles = snapshot.data!;
                if (profiles.isEmpty) {
                  return const Center(child: Text('No profile history available.'));
                }

                return ListView.builder(
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final status = profile['status'] ?? 'Pending';
                    final isApproved = profile['isApproved'] ?? false;
                    final displayStatus = status == 'Denied'
                        ? 'Denied'
                        : isApproved
                        ? 'Approved'
                        : 'Pending';

                    // Define colors for each status
                    Color statusColor;
                    switch (displayStatus) {
                      case 'Approved':
                        statusColor = Colors.green;
                        break;
                      case 'Denied':
                        statusColor = Colors.red;
                        break;
                      case 'Pending':
                      default:
                        statusColor = Colors.orange;
                        break;
                    }

                    final createdAt = (profile['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile['email'] ?? 'No Email',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text('Role: ${profile['role'] ?? 'N/A'}'),
                                Text('Full Name: ${profile['fullName'] ?? 'N/A'}'),
                                Text('Nickname: ${profile['nickName'] ?? 'N/A'}'),
                                Text('Status: $displayStatus'),
                                if (profile['role'] == 'agent' || profile['role'] == 'moderator')
                                  Text('Platform: ${profile['platform'] ?? 'N/A'}'),
                                Text('Created At: ${createdAt.toLocal().toString().split('.')[0]}'), // Display timestamp
                              ],
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                ),
                              ),
                              child: Text(
                                displayStatus,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _combineUserStreams() {
    // Stream for active users (Pending and Approved)
    final usersStream = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList());

    // Stream for denied users
    final deniedUsersStream = FirebaseFirestore.instance
        .collection('denied_users')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      data['status'] = 'Denied';
      return data;
    }).toList());

    // Combine the streams
    return usersStream.asyncMap((users) async {
      final deniedUsers = await deniedUsersStream.first;
      return [...users, ...deniedUsers];
    });
  }
}