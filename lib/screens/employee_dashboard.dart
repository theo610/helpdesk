import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EmployeeDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('My Tickets'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              // Create new ticket
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tickets')
            .where('createdBy', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final tickets = snapshot.data!.docs;
          if (tickets.isEmpty) {
            return Center(child: Text('No tickets created yet'));
          }

          return ListView.builder(
            itemCount: tickets.length,
            itemBuilder: (context, index) {
              final ticket = tickets[index];
              return Card(
                child: ListTile(
                  title: Text(ticket['title']),
                  subtitle: Text('Status: ${ticket['status']}'),
                  trailing: Chip(
                    label: Text(ticket['status']),
                    backgroundColor: _getStatusColor(ticket['status']),
                  ),
                  onTap: () {
                    // View ticket details
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'resolved': return Colors.green;
      case 'in_progress': return Colors.blue;
      default: return Colors.orange;
    }
  }
}