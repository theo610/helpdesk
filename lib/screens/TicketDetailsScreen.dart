import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ticket_model.dart';
import '../repositories/chat_repository.dart';
import 'chat_screen.dart';

class TicketDetailsScreen extends StatefulWidget {
  final String ticketId;
  final bool isAgent;
  final bool isEmployee; // Add flag to indicate if the user is an employee
  final bool initialFocusResponse;

  const TicketDetailsScreen({
    Key? key,
    required this.ticketId,
    this.isAgent = false,
    this.isEmployee = false, // Default to false
    this.initialFocusResponse = false,
  }) : super(key: key);

  @override
  _TicketDetailsScreenState createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ChatRepository _chatRepository = ChatRepository();
  Ticket? _ticket;
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _checkAuthenticationAndLoadData();
  }

  Future<void> _checkAuthenticationAndLoadData() async {
    if (_auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to view ticket details')),
      );
      // Replace with your navigation logic to the login screen
      // For example: Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    await _loadUserRole();
    await _loadTicketData();
  }

  Future<void> _loadUserRole() async {
    try {
      final userDoc = await _firestore.collection('users').doc(_auth.currentUser?.uid).get();
      if (userDoc.exists) {
        setState(() {
          _userRole = userDoc.data()?['role'] ?? 'unknown';
        });
      }
    } catch (e) {
      print('Error loading user role: $e');
    }
  }

  Future<void> _loadTicketData() async {
    setState(() => _isLoading = true);
    try {
      // Log the current user for debugging
      print('Current user UID: ${_auth.currentUser?.uid}');
      final userDoc = await _firestore.collection('users').doc(_auth.currentUser?.uid).get();
      print('User data: ${userDoc.data()}');

      // Load the ticket document
      final ticketDoc = await _firestore.collection('tickets').doc(widget.ticketId).get();
      print('Ticket data: ${ticketDoc.data()}');
      if (ticketDoc.exists) {
        final ticket = Ticket.fromFirestore(ticketDoc);
        // Validate required fields
        if (ticket.title.isEmpty || ticket.description.isEmpty) {
          throw Exception('Ticket data is incomplete');
        }
        setState(() {
          _ticket = ticket;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket not found')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading ticket: $e');
      if (e.toString().contains('permission-denied')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You do not have permission to view this ticket')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading ticket: $e')),
        );
      }
    }
  }

  Future<void> _startConversationWithCreator() async {
    if (_ticket == null) return;

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not signed in')),
      );
      return;
    }

    final ticketCreatorId = _ticket!.createdBy;

    if (currentUserId == ticketCreatorId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot chat with yourself')),
      );
      return;
    }

    try {
      final conversation = await _chatRepository.getOrCreateConversation(
        userId1: currentUserId,
        userId2: ticketCreatorId,
      );

      // Use the name stored in the ticket
      final creatorName = _ticket!.createdByName;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversation.id,
            otherUserId: ticketCreatorId,
            otherUserName: creatorName,
          ),
        ),
      );
    } catch (e) {
      print('Error starting conversation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting conversation: $e')),
      );
    }
  }

  void _showAgentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Change Status'),
                onTap: () {
                  Navigator.pop(context);
                  _showStatusChangeDialog(context);
                },
              ),
              if (_userRole == 'agent')
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('Send to Moderator'),
                  onTap: () {
                    Navigator.pop(context);
                    _showReassignDialog(context);
                  },
                ),
              if (_userRole == 'moderator')
                ListTile(
                  leading: const Icon(Icons.person_add),
                  title: const Text('Assign to Agent'),
                  onTap: () {
                    Navigator.pop(context);
                    _showAssignDialog(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showStatusChangeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Ticket Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Open'),
                leading: const Icon(Icons.circle, color: Colors.orange),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus('open');
                },
              ),
              ListTile(
                title: const Text('In Progress'),
                leading: const Icon(Icons.circle, color: Colors.blue),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus('in_progress');
                },
              ),
              ListTile(
                title: const Text('Resolved'),
                leading: const Icon(Icons.circle, color: Colors.green),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus('resolved');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateTicketStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      await _firestore.collection('tickets').doc(widget.ticketId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _loadTicketData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status updated successfully!')),
      );
    } catch (e) {
      print('Error updating status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e')),
      );
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  void _showReassignDialog(BuildContext context) {
    final TextEditingController detailsController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send to Moderator'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The ticket will be unassigned and sent to a moderator for reassignment.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: detailsController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Reassignment',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please provide a reason for reassignment';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  await _sendToModerator(detailsController.text.trim());
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendToModerator(String details) async {
    setState(() => _isUpdating = true);
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('User not signed in');
      }

      // Log the current user's role
      final userDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      final userRole = userDoc.data()?['role'] ?? 'unknown';
      print('Current user role: $userRole');

      // Log the data being written to reassigned_tickets
      final reassignmentData = {
        'ticketId': widget.ticketId,
        'previousAgentId': _ticket?.assignedTo ?? 'Unassigned',
        'newAgentId': null,
        'details': details,
        'reassignedBy': currentUserId,
        'sentToModeratorBy': currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
      };
      print('Writing to reassigned_tickets with data: $reassignmentData');

      // Step 1: Record the reassignment in the reassigned_tickets collection
      await _firestore.collection('reassigned_tickets').add(reassignmentData);

      // Step 2: Update the ticket's assignedTo field to null and mark as reassigned
      await _firestore.collection('tickets').doc(widget.ticketId).update({
        'assignedTo': null,
        'reassigned': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Step 3: Reload the ticket data to reflect the changes
      await _loadTicketData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket sent to moderator successfully!')),
      );
    } catch (e) {
      print('Error sending ticket to moderator: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending ticket to moderator: $e')),
      );
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  void _showAssignDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Assign to Agent'),
          content: FutureBuilder<QuerySnapshot>(
            future: _firestore
                .collection('users')
                .where('role', isEqualTo: 'agent')
                .where('platform', isEqualTo: _ticket?.platform)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final agents = snapshot.data!.docs;
              if (agents.isEmpty) {
                return const Text('No agents found for this platform.');
              }

              return SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: agents.length,
                  itemBuilder: (context, index) {
                    final agent = agents[index];
                    // Cast data() to Map<String, dynamic> to use containsKey
                    final agentData = agent.data() as Map<String, dynamic>;
                    final agentName = agentData.containsKey('fullName') && agentData['fullName'] != null
                        ? agentData['fullName']
                        : 'Agent ${agent.id}';
                    return ListTile(
                      title: Text(agentName),
                      onTap: () {
                        Navigator.pop(context);
                        _assignToAgent(agent.id);
                      },
                    );
                  },
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _assignToAgent(String agentId) async {
    setState(() => _isUpdating = true);
    try {
      // Fetch the current ticket data to get priority and status
      final ticketDoc = await _firestore.collection('tickets').doc(widget.ticketId).get();
      if (!ticketDoc.exists) {
        throw Exception('Ticket not found');
      }
      final ticketData = ticketDoc.data() as Map<String, dynamic>;
      final currentPriority = ticketData['priority'] as String;
      final currentStatus = ticketData['status'] as String;

      // Update the ticket with all required fields
      await _firestore.collection('tickets').doc(widget.ticketId).update({
        'assignedTo': agentId,
        'priority': currentPriority, // Include current priority
        'status': currentStatus, // Include current status
        'reassigned': false, // Reset reassigned status
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update the reassigned_tickets entry
      final reassignedDocs = await _firestore
          .collection('reassigned_tickets')
          .where('ticketId', isEqualTo: widget.ticketId)
          .where('newAgentId', isNull: true)
          .get();
      for (var doc in reassignedDocs.docs) {
        await doc.reference.update({
          'newAgentId': agentId,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      await _loadTicketData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket assigned successfully!')),
      );

      // Notify the parent to refresh the dashboard
      Navigator.pop(context, true);
    } catch (e) {
      print('Error assigning ticket: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error assigning ticket: $e')),
      );
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket Details'),
        actions: widget.isAgent
            ? [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _isUpdating ? null : () => _showAgentOptions(context),
          ),
        ]
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _loadTicketData,
        child: Stack(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _ticket == null
                ? const Center(child: Text('Ticket not found'))
                : _buildTicketDetails(),
            if (_isUpdating) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _ticket!.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(width: 8),
              // Only show "Reassigned" chip if the user is not an employee
              if (_ticket!.reassigned && !widget.isEmployee)
                const Chip(
                  label: Text(
                    'Reassigned',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.redAccent,
                  padding: EdgeInsets.symmetric(horizontal: 8),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _ticket!.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          // Display platform and equipment
          if (_ticket!.platform != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Platform: ${_ticket!.platform}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          if (_ticket!.equipment != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Equipment: ${_ticket!.equipment}',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          // Display assigned agent if assignedTo exists and user is not an employee
          if (_ticket!.assignedTo != null && !widget.isEmployee)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FutureBuilder<DocumentSnapshot>(
                future: _firestore.collection('users').doc(_ticket!.assignedTo).get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text(
                      'Loading agent details...',
                      style: TextStyle(fontSize: 16),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                    return const Text(
                      'Assigned to: Unknown Agent',
                      style: TextStyle(fontSize: 16),
                    );
                  }
                  final user = snapshot.data!;
                  final userData = user.data() as Map<String, dynamic>?;
                  final agentName = userData != null && userData.containsKey('fullName') && userData['fullName'] != null
                      ? userData['fullName']
                      : 'Agent ${user.id}';
                  return Text(
                    'Assigned to: $agentName',
                    style: const TextStyle(fontSize: 16),
                  );
                },
              ),
            ),
          // Display reassignment details only if the user is not an employee
          if (_ticket!.reassigned && !widget.isEmployee) ...[
            FutureBuilder<QuerySnapshot>(
              future: _firestore
                  .collection('reassigned_tickets')
                  .where('ticketId', isEqualTo: widget.ticketId)
                  .where('newAgentId', isNull: true) // Show only unassigned reassignments
                  .orderBy('timestamp', descending: true)
                  .limit(1)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: CircularProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  print('Error fetching reassignment details: ${snapshot.error}');
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Error loading reassignment details',
                      style: TextStyle(fontSize: 16, color: Colors.red),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Reassignment details not found',
                      style: TextStyle(fontSize: 16),
                    ),
                  );
                }

                final reassignmentDoc = snapshot.data!.docs.first;
                final sentToModeratorBy = reassignmentDoc['sentToModeratorBy'] as String?;
                final reassignmentReason = reassignmentDoc['details'] as String?;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sentToModeratorBy != null)
                      FutureBuilder<DocumentSnapshot>(
                        future: _firestore.collection('users').doc(sentToModeratorBy).get(),
                        builder: (context, userSnapshot) {
                          if (userSnapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Loading agent details...',
                                style: TextStyle(fontSize: 16),
                              ),
                            );
                          }
                          if (userSnapshot.hasError || !userSnapshot.hasData || !userSnapshot.data!.exists) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Sent to Moderator by: Unknown Agent',
                                style: TextStyle(fontSize: 16),
                              ),
                            );
                          }
                          final user = userSnapshot.data!;
                          final userData = user.data() as Map<String, dynamic>?;
                          final agentName = userData != null && userData.containsKey('fullName') && userData['fullName'] != null
                              ? userData['fullName']
                              : 'Agent ${user.id}';
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Sent to Moderator by: $agentName',
                              style: const TextStyle(fontSize: 16),
                            ),
                          );
                        },
                      ),
                    if (reassignmentReason != null && reassignmentReason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reason for Reassignment:',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              reassignmentReason,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isUpdating ? null : _startConversationWithCreator,
            child: const Text('Chat with Creator'),
          ),
        ],
      ),
    );
  }
}