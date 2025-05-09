import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ProfileDetailsScreen.dart';

class PendingRequestsScreen extends StatelessWidget {
  const PendingRequestsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pending Profile Requests',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('isApproved', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data!.docs;
                if (users.isEmpty) {
                  return const Center(child: Text('No profiles pending approval.'));
                }

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final createdAt = (user['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: ListTile(
                        title: Text(user['email']),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Role: ${user['role']}'),
                            Text('Full Name: ${user['fullName']}'),
                            Text('Nickname: ${user['nickName']}'),
                            Text('Phone: ${user['phoneNumber']}'),
                            Text('Address: ${user['address']}'),
                            Text('Country: ${user['country']}'),
                            Text('Gender: ${user['gender']}'),
                            if (user['role'] == 'agent' || user['role'] == 'moderator')
                              Text('Platform: ${user['platform']}'),
                            Text('Created At: ${createdAt.toLocal().toString().split('.')[0]}'), // Display timestamp
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileDetailsScreen(userId: user.id),
                            ),
                          );
                        },
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
}