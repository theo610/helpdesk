import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/ticket_model.dart';
import '../repositories/chat_repository.dart';
import 'chat_screen.dart';

class TicketDetailsScreen extends StatefulWidget {
  final String ticketId;
  final bool isAgent;
  final bool isEmployee;
  final bool initialFocusResponse;

  const TicketDetailsScreen({
    Key? key,
    required this.ticketId,
    this.isAgent = false,
    this.isEmployee = false,
    this.initialFocusResponse = false,
  }) : super(key: key);

  @override
  _TicketDetailsScreenState createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ChatRepository _chatRepository = ChatRepository();
  Ticket? _ticket;
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _userRole;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _checkAuthenticationAndLoadData();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthenticationAndLoadData() async {
    if (_auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please sign in to view ticket details', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
      final ticketDoc = await _firestore.collection('tickets').doc(widget.ticketId).get();
      if (ticketDoc.exists) {
        final ticket = Ticket.fromFirestore(ticketDoc);
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
          SnackBar(
            content: Text('Ticket not found', style: GoogleFonts.poppins()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading ticket: $e');
      if (e.toString().contains('permission-denied')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You do not have permission to view this ticket', style: GoogleFonts.poppins()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading ticket: $e', style: GoogleFonts.poppins()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _startConversationWithCreator() async {
    if (_ticket == null || _auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to start conversation', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final currentUserId = _auth.currentUser!.uid;
    final ticketCreatorId = _ticket!.createdBy;

    if (currentUserId == ticketCreatorId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You cannot chat with yourself', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    try {
      final conversation = await _chatRepository.getOrCreateConversation(
        userId1: currentUserId,
        userId2: ticketCreatorId,
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversation.id,
            otherUserId: ticketCreatorId,
            otherUserName: _ticket!.createdByName ?? 'Unknown',
          ),
        ),
      );
    } catch (e) {
      print('Error starting conversation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting conversation: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showAgentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                title: Text(
                  'Change Status',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showStatusChangeDialog(context);
                },
              ),
              if (_userRole == 'agent')
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    'Send to Moderator',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showReassignDialog(context);
                  },
                ),
              if (_userRole == 'moderator')
                ListTile(
                  leading: Icon(Icons.person_add, color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    'Assign to Agent',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
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
        return AnimatedScale(
          scale: 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Text(
                'Change Ticket Status',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    'Open',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  leading: Icon(Icons.circle, color: Colors.orange, size: 20),
                  onTap: () {
                    Navigator.pop(context);
                    _updateTicketStatus('open');
                  },
                ),
                ListTile(
                  title: Text(
                    'In Progress',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  leading: Icon(Icons.circle, color: Colors.blue, size: 20),
                  onTap: () {
                    Navigator.pop(context);
                    _updateTicketStatus('in_progress');
                  },
                ),
                ListTile(
                  title: Text(
                    'Closed',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  leading: Icon(Icons.circle, color: Colors.green, size: 20),
                  onTap: () {
                    Navigator.pop(context);
                    _updateTicketStatus('closed');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateTicketStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final ticketRef = _firestore.collection('tickets').doc(widget.ticketId);
      final currentTicketDoc = await ticketRef.get();
      if (!currentTicketDoc.exists) {
        throw Exception('Ticket not found');
      }
      final currentTicket = Ticket.fromFirestore(currentTicketDoc);

      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('User not signed in');
      }

      final ticketData = <String, dynamic>{
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // If the status is changing from 'open' to 'in_progress' and the user is an agent,
      // assign the ticket to the current user
      if (currentTicket.status == 'open' &&
          newStatus == 'in_progress' &&
          _userRole == 'agent') {
        ticketData['assignedTo'] = currentUserId;
        ticketData['reassigned'] = false;

        // Update any open reassignment records
        final reassignedDocs = await _firestore
            .collection('reassigned_tickets')
            .where('ticketId', isEqualTo: widget.ticketId)
            .where('newAgentId', isNull: true)
            .get();
        for (var doc in reassignedDocs.docs) {
          await doc.reference.update({
            'newAgentId': currentUserId,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      }

      if (newStatus == 'in_progress' && currentTicket.firstResponseAt == null) {
        ticketData['firstResponseAt'] = FieldValue.serverTimestamp();
      }

      if (newStatus == 'closed' && currentTicket.resolvedAt == null) {
        ticketData['resolvedAt'] = FieldValue.serverTimestamp();
      }

      await ticketRef.update(ticketData);
      await _loadTicketData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Error updating status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  void _showReassignDialog(BuildContext context) {
    final TextEditingController detailsController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isFocused = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Text(
                    'Send to Moderator',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'The ticket will be unassigned and sent to a moderator for reassignment.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          label: 'Reassignment reason input, required',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reason for Reassignment *',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              AnimatedScale(
                                scale: isFocused ? 1.02 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: detailsController,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Enter reason',
                                      hintStyle: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    maxLines: 3,
                                    onChanged: (value) {
                                      setState(() {});
                                    },
                                    onTap: () {
                                      setState(() {
                                        isFocused = true;
                                      });
                                    },
                                    onEditingComplete: () {
                                      setState(() {
                                        isFocused = false;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (detailsController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Reason for reassignment is required', style: GoogleFonts.poppins()),
                            backgroundColor: Theme.of(context).colorScheme.error,
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      await _sendToModerator(detailsController.text.trim());
                    },
                    child: Text(
                      'Send',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
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

      final userDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }

      final reassignmentData = {
        'ticketId': widget.ticketId,
        'previousAgentId': _ticket?.assignedTo ?? 'Unassigned',
        'newAgentId': null,
        'details': details,
        'reassignedBy': currentUserId,
        'sentToModeratorBy': currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('reassigned_tickets').add(reassignmentData);

      await _firestore.collection('tickets').doc(widget.ticketId).update({
        'assignedTo': null,
        'reassigned': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _loadTicketData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket sent to moderator successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Error sending ticket to moderator: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending ticket to moderator: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  void _showAssignDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AnimatedScale(
          scale: 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Text(
                'Assign to Agent',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
            content: FutureBuilder<QuerySnapshot>(
              future: _firestore
                  .collection('users')
                  .where('role', isEqualTo: 'agent')
                  .where('platform', isEqualTo: _ticket?.platform)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                    ),
                  );
                }

                final agents = snapshot.data!.docs;
                if (agents.isEmpty) {
                  return Text(
                    'No agents found for this platform.',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  );
                }

                return SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: agents.length,
                    itemBuilder: (context, index) {
                      final agent = agents[index];
                      final agentData = agent.data() as Map<String, dynamic>;
                      final agentName = agentData.containsKey('fullName') && agentData['fullName'] != null
                          ? agentData['fullName']
                          : 'Agent ${agent.id}';
                      return ListTile(
                        leading: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                        title: Text(
                          agentName,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
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
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _assignToAgent(String agentId) async {
    setState(() => _isUpdating = true);
    try {
      final ticketDoc = await _firestore.collection('tickets').doc(widget.ticketId).get();
      if (!ticketDoc.exists) {
        throw Exception('Ticket not found');
      }
      final ticketData = ticketDoc.data() as Map<String, dynamic>;
      final currentPriority = ticketData['priority'] as String;
      final currentStatus = ticketData['status'] as String;

      await _firestore.collection('tickets').doc(widget.ticketId).update({
        'assignedTo': agentId,
        'priority': currentPriority,
        'status': currentStatus,
        'reassigned': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
        SnackBar(
          content: Text('Ticket assigned successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      print('Error assigning ticket: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error assigning ticket: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.background,
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadTicketData,
            color: Theme.of(context).colorScheme.primary,
            child: Stack(
              children: [
                _buildContent(),
                if (_isLoading || _isUpdating)
                  Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SizedBox();
    }
    if (_ticket == null) {
      return Center(
        child: Text(
          'Ticket not found',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    final uniqueId = '${_ticket!.id.substring(0, 8)}-${DateFormat('yyMMddHHmm').format(_ticket!.createdAt)}';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Semantics(
                                  label: 'Ticket status',
                                  child: Chip(
                                    label: Text(
                                      _ticket!.status.replaceAll('_', ' ').toUpperCase(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onPrimary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    backgroundColor: _ticket!.status == 'open'
                                        ? Colors.orange
                                        : _ticket!.status == 'in_progress'
                                        ? Colors.blue
                                        : Colors.green,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_ticket!.reassigned && !widget.isEmployee)
                                  Semantics(
                                    label: 'Reassigned status',
                                    child: Chip(
                                      label: Text(
                                        'Reassigned',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onError,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      backgroundColor: Theme.of(context).colorScheme.error,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              label: 'Ticket title',
                              child: Text(
                                _ticket!.title,
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              label: 'Ticket ID',
                              child: Chip(
                                label: Text(
                                  'ID: $uniqueId',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 1,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Details',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              label: 'Ticket description',
                              child: ListTile(
                                leading: Icon(Icons.description, color: Theme.of(context).colorScheme.primary),
                                title: Text(
                                  _ticket!.description,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            if (_ticket!.platform != null)
                              Semantics(
                                label: 'Platform',
                                child: ListTile(
                                  leading: Icon(Icons.computer, color: Theme.of(context).colorScheme.primary),
                                  title: Text(
                                    _ticket!.platform!,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            if (_ticket!.equipment != null)
                              Semantics(
                                label: 'Equipment',
                                child: ListTile(
                                  leading: Icon(Icons.build, color: Theme.of(context).colorScheme.primary),
                                  title: Text(
                                    _ticket!.equipment!,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    maxLines: null,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            if (_ticket!.assignedTo != null)
                              Semantics(
                                label: 'Assigned agent',
                                child: FutureBuilder<DocumentSnapshot>(
                                  future: _firestore.collection('users').doc(_ticket!.assignedTo).get(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return ListTile(
                                        leading: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                                        title: Text(
                                          'Loading agent details...',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                      );
                                    }
                                    if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                                      return ListTile(
                                        leading: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                                        title: Text(
                                          'Unknown Agent',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                      );
                                    }
                                    final user = snapshot.data!;
                                    final userData = user.data() as Map<String, dynamic>?;
                                    final agentName = userData != null &&
                                        userData.containsKey('fullName') &&
                                        userData['fullName'] != null
                                        ? userData['fullName']
                                        : 'Agent ${user.id}';
                                    return ListTile(
                                      leading: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                                      title: Text(
                                        agentName,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_ticket!.reassigned && !widget.isEmployee) ...[
                  const SizedBox(height: 16),
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: Theme.of(context).colorScheme.surface,
                        child: ExpansionTile(
                          title: Text(
                            'Reassignment Details',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          leading: Icon(Icons.swap_horiz, color: Theme.of(context).colorScheme.primary),
                          childrenPadding: const EdgeInsets.all(16),
                          children: [
                            FutureBuilder<QuerySnapshot>(
                              future: _firestore
                                  .collection('reassigned_tickets')
                                  .where('ticketId', isEqualTo: widget.ticketId)
                                  .where('newAgentId', isNull: true)
                                  .orderBy('timestamp', descending: true)
                                  .limit(1)
                                  .get(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const CircularProgressIndicator();
                                }
                                if (snapshot.hasError) {
                                  print('Error fetching reassignment details: ${snapshot.error}');
                                  return Text(
                                    'Error loading reassignment details',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  );
                                }
                                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                  return Text(
                                    'Reassignment details not found',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Theme.of(context).colorScheme.onSurface,
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
                                      Semantics(
                                        label: 'Sent to moderator by',
                                        child: FutureBuilder<DocumentSnapshot>(
                                          future: _firestore.collection('users').doc(sentToModeratorBy).get(),
                                          builder: (context, userSnapshot) {
                                            if (userSnapshot.connectionState == ConnectionState.waiting) {
                                              return Text(
                                                'Loading agent details...',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w400,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                ),
                                              );
                                            }
                                            if (userSnapshot.hasError ||
                                                !userSnapshot.hasData ||
                                                !userSnapshot.data!.exists) {
                                              return Text(
                                                'Sent to Moderator by: Unknown Agent',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w400,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                ),
                                              );
                                            }
                                            final user = userSnapshot.data!;
                                            final userData = user.data() as Map<String, dynamic>?;
                                            final agentName = userData != null &&
                                                userData.containsKey('fullName') &&
                                                userData['fullName'] != null
                                                ? userData['fullName']
                                                : 'Agent ${user.id}';
                                            return Text(
                                              'Sent to Moderator by: $agentName',
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w400,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    if (reassignmentReason != null && reassignmentReason.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Semantics(
                                        label: 'Reason for reassignment',
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Reason',
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              reassignmentReason,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w400,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            children: [
              const Spacer(),
              Semantics(
                label: 'Chat with ticket creator',
                child: AnimatedScale(
                  scale: 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: GestureDetector(
                      onTapDown: (_) => setState(() {}),
                      onTapUp: (_) => _startConversationWithCreator(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary.withOpacity(0.9),
                              Theme.of(context).colorScheme.secondary.withOpacity(0.9),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Chat with Creator',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Ticket Details',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onBackground,
          ),
        ),
        if (widget.isAgent)
          Semantics(
            label: 'Edit ticket options',
            child: IconButton(
              icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
              onPressed: _isUpdating ? null : () => _showAgentOptions(context),
            ),
          ),
      ],
    );
  }
}