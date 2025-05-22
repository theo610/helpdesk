import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../models/ticket_model.dart';
import 'TicketDetailsScreen.dart';
import 'AssignEquipmentScreen.dart';
import 'Stats_Screen.dart';

class SearchBar extends StatefulWidget {
  final String initialQuery;
  final Function(String) onSearchChanged;
  final VoidCallback onClear;

  const SearchBar({
    Key? key,
    required this.initialQuery,
    required this.onSearchChanged,
    required this.onClear,
  }) : super(key: key);

  @override
  _SearchBarState createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  late TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(SearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.initialQuery) {
      _controller.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Search tickets',
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 500),
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
            controller: _controller,
            autofocus: true,
            style: GoogleFonts.poppins(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: 'Search tickets...',
              hintStyle: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, color: Theme.of(context).colorScheme.primary),
                onPressed: () {
                  _controller.clear();
                  widget.onClear();
                },
              )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            ),
            onChanged: (value) {
              setState(() {});
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () {
                widget.onSearchChanged(value);
              });
            },
          ),
        ),
      ),
    );
  }
}

class ModeratorDashboard extends StatefulWidget {
  const ModeratorDashboard({Key? key}) : super(key: key);

  @override
  _ModeratorDashboardState createState() => _ModeratorDashboardState();
}

class _ModeratorDashboardState extends State<ModeratorDashboard> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final int _pageSize = 15;
  DocumentSnapshot? _lastReassignedDocument;
  DocumentSnapshot? _lastPlatformDocument;
  bool _hasMoreReassigned = true;
  bool _hasMorePlatform = true;
  bool _isLoadingMoreReassigned = false;
  bool _isLoadingMorePlatform = false;
  bool _isLoadingSearch = false;
  bool _isSearchMode = false;
  bool _isLoadingPlatform = true; // New flag for platform loading
  String _filterStatus = 'all';
  String _searchQuery = '';
  String? _priorityFilter;
  String? _platformFilter;
  List<Ticket> _reassignedTickets = [];
  List<Ticket> _platformTickets = [];
  final ScrollController _scrollController = ScrollController();
  late AnimationController _dialogAnimationController;
  late Animation<double> _dialogScaleAnimation;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _dialogAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _dialogScaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _dialogAnimationController, curve: Curves.easeOut),
    );
    _isLoadingPlatform = true; // Set loading state
    _loadModeratorPlatform().then((_) {
      setState(() {
        _isLoadingPlatform = false; // Platform loading complete
      });
      if (_platformFilter != null) {
        _loadInitialReassignedTickets();
        _loadInitialPlatformTickets();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dialogAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadModeratorPlatform() async {
    try {
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      var role = userDoc['role'] as String?;
      var platform = userDoc['platform'] as String?;
      if (role != 'moderator') {
        throw Exception('User is not a moderator: role=$role');
      }
      if (platform != null) {
        setState(() => _platformFilter = platform.trim());
      } else {
        throw Exception('Moderator platform not set');
      }
    } catch (e) {
      print('Error loading moderator platform: $e');
      setState(() => _platformFilter = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Platform not set. Please update your profile.', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoadingPlatform = false); // Ensure loading state is updated
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent && !_isSearchMode) {
      if (_hasMoreReassigned && !_isLoadingMoreReassigned) {
        _loadMoreReassignedTickets();
      } else if (_hasMorePlatform && !_isLoadingMorePlatform) {
        _loadMorePlatformTickets();
      }
    }
  }

  Future<void> _loadInitialReassignedTickets() async {
    setState(() {
      _reassignedTickets = [];
      _lastReassignedDocument = null;
      _hasMoreReassigned = true;
      _isLoadingMoreReassigned = false;
    });
    await _loadMoreReassignedTickets();
  }

  Future<void> _loadMoreReassignedTickets() async {
    if (!_hasMoreReassigned || _isLoadingMoreReassigned || _platformFilter == null || _isSearchMode) {
      return;
    }

    setState(() => _isLoadingMoreReassigned = true);

    try {
      var reassignedQuery = firestore
          .collection('reassigned_tickets')
          .where('newAgentId', isNull: true)
          .orderBy('timestamp', descending: true);

      if (_lastReassignedDocument != null) {
        reassignedQuery = reassignedQuery.startAfterDocument(_lastReassignedDocument!);
      }

      reassignedQuery = reassignedQuery.limit(_pageSize);

      final reassignedSnapshot = await reassignedQuery.get();
      if (reassignedSnapshot.docs.isEmpty) {
        setState(() => _hasMoreReassigned = false);
        setState(() => _isLoadingMoreReassigned = false);
        return;
      }

      final ticketIds = reassignedSnapshot.docs.map((doc) => doc['ticketId'] as String).toList();
      const batchSize = 10;
      final List<Ticket> newTickets = [];

      for (var i = 0; i < ticketIds.length; i += batchSize) {
        final batch = ticketIds.sublist(i, i + batchSize > ticketIds.length ? ticketIds.length : i + batchSize);
        var ticketsQuery = firestore
            .collection('tickets')
            .where('platform', isEqualTo: _platformFilter)
            .where('reassigned', isEqualTo: true)
            .where(FieldPath.documentId, whereIn: batch)
            .orderBy('createdAt', descending: true);

        final ticketsSnapshot = await ticketsQuery.get();
        newTickets.addAll(
          ticketsSnapshot.docs
              .map(Ticket.fromFirestore)
              .where((ticket) => ticket.assignedTo == null)
              .toList(),
        );
      }

      if (newTickets.isEmpty) {
        setState(() => _hasMoreReassigned = false);
      } else {
        _lastReassignedDocument = reassignedSnapshot.docs.last;
        setState(() => _reassignedTickets = [..._reassignedTickets, ...newTickets]);
      }
    } catch (e) {
      print('Error loading reassigned tickets: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading reassigned tickets: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoadingMoreReassigned = false);
    }
  }

  Future<void> _loadInitialPlatformTickets() async {
    setState(() {
      _platformTickets = [];
      _lastPlatformDocument = null;
      _hasMorePlatform = true;
      _isLoadingMorePlatform = false;
    });
    await _loadMorePlatformTickets();
  }

  Future<void> _loadMorePlatformTickets() async {
    if (!_hasMorePlatform || _isLoadingMorePlatform || _platformFilter == null || _isSearchMode) {
      return;
    }

    setState(() => _isLoadingMorePlatform = true);

    try {
      var query = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: false)
          .orderBy('createdAt', descending: true);

      if (_filterStatus != 'all') {
        query = query.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        final priorityString = _priorityFilter!.toLowerCase();
        query = query.where('priority', isEqualTo: priorityString);
      }

      query = query.limit(_pageSize);

      if (_lastPlatformDocument != null) {
        query = query.startAfterDocument(_lastPlatformDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        setState(() => _hasMorePlatform = false);
      } else {
        _lastPlatformDocument = snapshot.docs.last;
        setState(() => _platformTickets = [
          ..._platformTickets,
          ...snapshot.docs.map(Ticket.fromFirestore),
        ]);
      }
    } catch (e) {
      print('Error loading platform tickets: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading platform tickets: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoadingMorePlatform = false);
    }
  }

  Future<void> _searchTickets(String query) async {
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      setState(() {
        _isLoadingSearch = false;
        _isSearchMode = false;
      });
      await _loadInitialReassignedTickets();
      await _loadInitialPlatformTickets();
      return;
    }

    if (_platformFilter == null) {
      setState(() {
        _isLoadingSearch = false;
        _isSearchMode = false;
      });
      return;
    }

    setState(() {
      _isLoadingSearch = true;
      _isSearchMode = true;
      _reassignedTickets = [];
      _platformTickets = [];
      _hasMoreReassigned = false;
      _hasMorePlatform = false;
    });

    try {
      var reassignedTitleQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: true)
          .orderBy('title')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        reassignedTitleQuery = reassignedTitleQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        reassignedTitleQuery = reassignedTitleQuery.where('priority', isEqualTo: _priorityFilter);
      }

      var reassignedDescQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: true)
          .orderBy('description')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        reassignedDescQuery = reassignedDescQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        reassignedDescQuery = reassignedDescQuery.where('priority', isEqualTo: _priorityFilter);
      }

      var platformTitleQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: false)
          .orderBy('title')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        platformTitleQuery = platformTitleQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        platformTitleQuery = platformTitleQuery.where('priority', isEqualTo: _priorityFilter);
      }

      var platformDescQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: false)
          .orderBy('description')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        platformDescQuery = platformDescQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        platformDescQuery = platformDescQuery.where('priority', isEqualTo: _priorityFilter);
      }

      final reassignedTitleSnapshot = await reassignedTitleQuery.get();
      final reassignedDescSnapshot = await reassignedDescQuery.get();
      final platformTitleSnapshot = await platformTitleQuery.get();
      final platformDescSnapshot = await platformDescQuery.get();

      final reassignedTicketDocs = <String, Ticket>{};
      for (var doc in reassignedTitleSnapshot.docs) {
        reassignedTicketDocs[doc.id] = Ticket.fromFirestore(doc);
      }
      for (var doc in reassignedDescSnapshot.docs) {
        reassignedTicketDocs[doc.id] = Ticket.fromFirestore(doc);
      }

      final platformTicketDocs = <String, Ticket>{};
      for (var doc in platformTitleSnapshot.docs) {
        platformTicketDocs[doc.id] = Ticket.fromFirestore(doc);
      }
      for (var doc in platformDescSnapshot.docs) {
        platformTicketDocs[doc.id] = Ticket.fromFirestore(doc);
      }

      setState(() {
        _reassignedTickets = reassignedTicketDocs.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _platformTickets = platformTicketDocs.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error searching tickets: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoadingSearch = false);
    }
  }

  Future<void> _updateTicketStatus(String ticketId, String newStatus) async {
    try {
      final ticketRef = firestore.collection('tickets').doc(ticketId);
      final currentTicketDoc = await ticketRef.get();
      final currentTicket = Ticket.fromFirestore(currentTicketDoc);

      final ticketData = <String, dynamic>{
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == 'in_progress' && currentTicket.firstResponseAt == null) {
        ticketData['firstResponseAt'] = FieldValue.serverTimestamp();
      }
      if (newStatus == 'resolved' && currentTicket.resolvedAt == null) {
        ticketData['resolvedAt'] = FieldValue.serverTimestamp();
      }

      await ticketRef.update(ticketData);
      _loadInitialReassignedTickets();
      _loadInitialPlatformTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket status updated!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating ticket: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _assignTicket(String ticketId, String newAgentId) async {
    try {
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      final userRole = userDoc.data()!['role'] as String? ?? 'unknown';
      if (userRole != 'moderator') {
        throw Exception('Only moderators can assign tickets to agents');
      }

      final ticketDoc = await firestore.collection('tickets').doc(ticketId).get();
      if (!ticketDoc.exists) {
        throw Exception('Ticket not found');
      }
      final ticketData = ticketDoc.data()! as Map<String, dynamic>;
      final ticketPlatform = ticketData['platform'] as String;
      final currentPriority = ticketData['priority'] as String;
      final currentStatus = ticketData['status'] as String;

      if (ticketPlatform != _platformFilter) {
        throw Exception('Platform mismatch: Ticket platform ($ticketPlatform) does not match moderator platform ($_platformFilter)');
      }

      await firestore.runTransaction((transaction) async {
        final ticketRef = firestore.collection('tickets').doc(ticketId);
        transaction.update(ticketRef, {
          'assignedTo': newAgentId,
          'priority': currentPriority,
          'status': currentStatus,
          'reassigned': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final reassignedDocs = await firestore
            .collection('reassigned_tickets')
            .where('ticketId', isEqualTo: ticketId)
            .where('newAgentId', isNull: true)
            .get();
        if (reassignedDocs.docs.isEmpty) {
          throw Exception('No pending reassignment found for this ticket');
        }
        for (var doc in reassignedDocs.docs) {
          transaction.update(doc.reference, {
            'newAgentId': newAgentId,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      });

      await _loadInitialReassignedTickets();
      await _loadInitialPlatformTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket assigned!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Error assigning ticket: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error assigning ticket: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showTicketOptions(BuildContext context, Ticket ticket) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                title: Text(
                  'Change Status',
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showStatusChangeDialog(context, ticket);
                },
              ),
              ListTile(
                leading: Icon(Icons.person_add, color: Theme.of(context).colorScheme.primary),
                title: Text(
                  'Assign Ticket',
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAssignDialog(context, ticket);
                },
              ),
              ListTile(
                leading: Icon(Icons.chat, color: Theme.of(context).colorScheme.primary),
                title: Text(
                  'Add Response',
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _viewTicketDetails(context, ticket.id, initialFocusResponse: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showStatusChangeDialog(BuildContext context, Ticket ticket) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'Change Ticket Status',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Open', style: GoogleFonts.poppins()),
                leading: const Icon(Icons.circle, color: Colors.orange, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus(ticket.id, 'open');
                },
              ),
              ListTile(
                title: Text('In Progress', style: GoogleFonts.poppins()),
                leading: const Icon(Icons.circle, color: Colors.blue, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus(ticket.id, 'in_progress');
                },
              ),
              ListTile(
                title: Text('Resolved', style: GoogleFonts.poppins()),
                leading: const Icon(Icons.circle, color: Colors.green, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus(ticket.id, 'resolved');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAssignDialog(BuildContext context, Ticket ticket) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'Assign Ticket',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          content: FutureBuilder<QuerySnapshot>(
            future: firestore
                .collection('users')
                .where('role', isEqualTo: 'agent')
                .where('platform', isEqualTo: _platformFilter)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              }

              final agents = snapshot.data!.docs;
              return SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: agents.length,
                  itemBuilder: (context, index) {
                    final agent = agents[index];
                    final agentData = agent.data() as Map<String, dynamic>;
                    final agentName = agentData.containsKey('fullName') &&
                        agentData['fullName'] != null
                        ? agentData['fullName']
                        : 'Agent ${agent.id}';
                    return ListTile(
                      title: Text(
                        agentName,
                        style: GoogleFonts.poppins(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _assignTicket(ticket.id, agent.id);
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
                style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: NavigationDrawer(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              'Moderator Menu',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.dashboard, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              'Ticket Dashboard',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            selectedIcon: Icon(Icons.dashboard, color: Theme.of(context).colorScheme.primary),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.settings_applications, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              'Assign Equipment',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            selectedIcon: Icon(Icons.settings_applications, color: Theme.of(context).colorScheme.primary),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.bar_chart, color: Theme.of(context).colorScheme.onSurface),
            label: Text(
              'Statistics',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            selectedIcon: Icon(Icons.bar_chart, color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
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
          child: Column(
            children: [
              _buildHeader(),
              if (_selectedIndex == 0 && _isSearchMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: SearchBar(
                    initialQuery: _searchQuery,
                    onSearchChanged: _searchTickets,
                    onClear: () {
                      setState(() {
                        _searchQuery = '';
                        _isSearchMode = false;
                      });
                      _searchTickets('');
                    },
                  ),
                ),
              Expanded(child: _buildScreen()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    icon: Icon(
                      Icons.menu,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    tooltip: 'Open menu',
                  ),
                ),
                Flexible(
                  child: Text(
                    _selectedIndex == 0
                        ? 'Platform Tickets'
                        : _selectedIndex == 1
                        ? 'Assign Equipment'
                        : 'Statistics',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onBackground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (_selectedIndex == 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _isSearchMode ? Icons.cancel : Icons.search,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  onPressed: () {
                    setState(() {
                      _isSearchMode = !_isSearchMode;
                      if (!_isSearchMode) {
                        _searchQuery = '';
                        _searchTickets('');
                      }
                    });
                  },
                  tooltip: _isSearchMode ? 'Cancel Search' : 'Search Tickets',
                ),
                _buildFilterMenu(),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  onPressed: _isSearchMode
                      ? null
                      : () {
                    _loadInitialReassignedTickets();
                    _loadInitialPlatformTickets();
                  },
                  tooltip: 'Refresh Tickets',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilterMenu() {
    return IconButton(
      icon: Icon(
        Icons.filter_alt,
        color: Theme.of(context).colorScheme.primary,
        size: 24,
      ),
      onPressed: _showFilterDialog,
      tooltip: 'Filter Tickets',
    );
  }

  void _showFilterDialog() {
    _dialogAnimationController.forward(from: 0);
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return ScaleTransition(
              scale: _dialogScaleAnimation,
              child: AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                title: Text(
                  'Filter Tickets',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                content: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Status',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          label: 'Status filter',
                          child: AnimatedOpacity(
                            opacity: 1.0,
                            duration: const Duration(milliseconds: 500),
                            child: DropdownButtonFormField<String>(
                              value: _filterStatus,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceVariant,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 1,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              dropdownColor: Theme.of(context).colorScheme.surface,
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              selectedItemBuilder: (context) => [
                                'all',
                                'open',
                                'in_progress',
                                'resolved',
                              ].map((value) => Text(
                                value == 'all'
                                    ? 'All Statuses'
                                    : value == 'open'
                                    ? 'Open'
                                    : value == 'in_progress'
                                    ? 'In Progress'
                                    : 'Resolved',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              )).toList(),
                              items: [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text(
                                    'All Statuses',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'open',
                                  child: Row(
                                    children: [
                                      Icon(Icons.circle, color: Colors.orange, size: 20),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Open',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'in_progress',
                                  child: Row(
                                    children: [
                                      Icon(Icons.circle, color: Colors.blue, size: 20),
                                      const SizedBox(width: 16),
                                      Text(
                                        'In Progress',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'resolved',
                                  child: Row(
                                    children: [
                                      Icon(Icons.circle, color: Colors.green, size: 20),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Resolved',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (value) => setState(() => _filterStatus = value!),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Priority',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          label: 'Priority filter',
                          child: AnimatedOpacity(
                            opacity: 1.0,
                            duration: const Duration(milliseconds: 500),
                            child: DropdownButtonFormField<String>(
                              value: _priorityFilter,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceVariant,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 1,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              dropdownColor: Theme.of(context).colorScheme.surface,
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              selectedItemBuilder: (context) => [
                                null,
                                'low',
                                'medium',
                                'high',
                                'critical',
                              ].map((value) => Text(
                                value == null
                                    ? 'All Priorities'
                                    : value == 'low'
                                    ? 'Low'
                                    : value == 'medium'
                                    ? 'Medium'
                                    : value == 'high'
                                    ? 'High'
                                    : 'Critical',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              )).toList(),
                              items: [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text(
                                    'All Priorities',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'low',
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag, color: Colors.green, size: 20),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Low',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'medium',
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag, color: Colors.blue, size: 20),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Medium',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'high',
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag, color: Colors.orange, size: 20),
                                      const SizedBox(width: 16),
                                      Text(
                                        'High',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'critical',
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag, color: Colors.red, size: 20),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Critical',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (value) => setState(() => _priorityFilter = value),
                            ),
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (_isSearchMode) {
                        _searchTickets(_searchQuery);
                      } else {
                        _loadInitialReassignedTickets();
                        _loadInitialPlatformTickets();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: Text(
                      'Apply',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w500,
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

  Widget _buildScreen() {
    switch (_selectedIndex) {
      case 0:
        return Stack(
          children: [
            if (_isLoadingPlatform) // Show loading while platform is being fetched
              Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              )
            else if (_platformFilter == null) // Show error only after platform check
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Platform not set. Please complete your profile.',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              _buildTicketList(),
            if (_isLoadingSearch)
              Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        );
      case 1:
        return const AssignEquipmentScreen();
      case 2:
        return const StatsScreen();
      default:
        return Center(
          child: Text(
            'Screen not found',
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        );
    }
  }

  Widget _buildTicketList() {
    final allTickets = [..._reassignedTickets, ..._platformTickets];
    if (allTickets.isEmpty  && !_isLoadingMoreReassigned && !_isLoadingMorePlatform && !_isLoadingSearch) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _isSearchMode ? 'No tickets match your search' : 'No tickets found in your platform',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_filterStatus != 'all' || _priorityFilter != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _filterStatus = 'all';
                    _priorityFilter = null;
                  });
                  if (_isSearchMode) {
                    _searchTickets(_searchQuery);
                  } else {
                    _loadInitialReassignedTickets();
                    _loadInitialPlatformTickets();
                  }
                },
                child: Text(
                  'Clear filters',
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _isSearchMode
          ? () => _searchTickets(_searchQuery)
          : () async {
        await _loadInitialReassignedTickets();
        await _loadInitialPlatformTickets();
      },
      child: AnimationLimiter(
        child: ListView.builder(
          key: const Key('ticketList'),
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: allTickets.length +
              (_hasMoreReassigned && _isLoadingMoreReassigned && !_isSearchMode ? 1 : 0) +
              (_hasMorePlatform && _isLoadingMorePlatform && !_isSearchMode ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= allTickets.length) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              );
            }
            final ticket = allTickets[index];
            final isReassigned = _reassignedTickets.contains(ticket);
            return AnimationConfiguration.staggeredList(
              position: index,
              duration: const Duration(milliseconds: 375),
              child: SlideAnimation(
                verticalOffset: 50.0,
                child: FadeInAnimation(
                  child: _buildTicketCard(ticket, isReassigned),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTicketCard(Ticket ticket, bool isReassigned) {
    final uniqueId = '${ticket.id.substring(0, 8)}-${DateFormat('yyMMddHHmm').format(ticket.createdAt)}';

    return Semantics(
      label: 'Ticket, tap to view, long press for options',
      child: Card(
        color: Theme.of(context).colorScheme.surface,
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _viewTicketDetails(context, ticket.id),
          onLongPress: () => _showTicketOptions(context, ticket),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              ticket.title,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isReassigned)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Reassigned',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _buildPriorityIcon(ticket.priority),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatusChip(ticket.status),
                    const SizedBox(width: 12),
                    Text(
                      'ID: $uniqueId',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('MMM dd, yyyy • HH:mm').format(ticket.createdAt),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (ticket.assignedTo != null) ...[
                  const SizedBox(height: 8),
                  FutureBuilder<DocumentSnapshot>(
                    future: firestore.collection('users').doc(ticket.assignedTo).get(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final user = snapshot.data!;
                        final userData = user.data() as Map<String, dynamic>?;
                        final agentName = userData != null &&
                            userData.containsKey('fullName') &&
                            userData['fullName'] != null
                            ? userData['fullName']
                            : 'Agent ${user.id}';
                        return Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Assigned to: $agentName',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ],
                if (ticket.platform != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.build,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Platform: ${ticket.platform}',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (ticket.equipment != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.devices,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Equipment: ${ticket.equipment}',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (ticket.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    ticket.description,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityIcon(String priority) {
    final priorityData = {
      'low': {'icon': Icons.flag, 'color': Colors.green},
      'medium': {'icon': Icons.flag, 'color': Colors.blue},
      'high': {'icon': Icons.flag, 'color': Colors.orange},
      'critical': {'icon': Icons.flag, 'color': Colors.red},
    };
    return Semantics(
      label: 'Priority: $priority',
      child: Tooltip(
        message: priority.toUpperCase(),
        child: Icon(
          priorityData[priority]!['icon'] as IconData,
          color: priorityData[priority]!['color'] as Color,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final statusColors = {
      'open': Colors.orange,
      'in_progress': Colors.blue,
      'resolved': Colors.green,
      'closed': Colors.grey,
    };

    return Semantics(
      label: 'Status: ${status.replaceAll('_', ' ').toUpperCase()}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: statusColors[status] ?? Colors.grey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          status.replaceAll('_', ' ').toUpperCase(),
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _viewTicketDetails(BuildContext context, String ticketId, {bool initialFocusResponse = false}) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => TicketDetailsScreen(
          ticketId: ticketId,
          isAgent: true,
          initialFocusResponse: initialFocusResponse,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var slideTween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(slideTween),
            child: FadeTransition(
              opacity: animation.drive(fadeTween),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket updated!', style: GoogleFonts.poppins()),
          duration: Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      _loadInitialReassignedTickets();
      _loadInitialPlatformTickets();
    }
  }
}