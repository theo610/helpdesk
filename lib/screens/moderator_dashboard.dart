import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/ticket_model.dart';
import 'ticketDetailsScreen.dart';

// Reusing the SearchBar widget from AgentDashboard
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
    return TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Search tickets...',
        border: const OutlineInputBorder(),
        hintStyle: const TextStyle(color: Colors.grey),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            _controller.clear();
            widget.onClear();
          },
        )
            : null,
      ),
      onChanged: (value) {
        setState(() {}); // To update the suffixIcon visibility
        if (_debounce?.isActive ?? false) _debounce!.cancel();
        _debounce = Timer(const Duration(milliseconds: 500), () {
          widget.onSearchChanged(value);
        });
      },
    );
  }
}

class ModeratorDashboard extends StatefulWidget {
  const ModeratorDashboard({Key? key}) : super(key: key);

  @override
  _ModeratorDashboardState createState() => _ModeratorDashboardState();
}

class _ModeratorDashboardState extends State<ModeratorDashboard> {
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

  String _filterStatus = 'all';
  String _searchQuery = '';
  String? _priorityFilter;
  String? _platformFilter;

  List<Ticket> _reassignedTickets = [];
  List<Ticket> _platformTickets = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadModeratorPlatform().then((_) {
      _loadInitialReassignedTickets();
      _loadInitialPlatformTickets();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
      print('Moderator role: $role, platform: $platform');
      if (role != 'moderator') {
        throw Exception('User is not a moderator: role=$role');
      }
      if (platform != null) {
        // Normalize platform name to handle special characters or whitespace
        setState(() => _platformFilter = platform.trim());
      } else {
        throw Exception('Moderator platform not set');
      }
    } catch (e) {
      print('Error loading moderator platform: $e');
      setState(() => _platformFilter = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Platform not set. Please update your profile.')),
      );
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent &&
        !_isSearchMode) {
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
    if (!_hasMoreReassigned ||
        _isLoadingMoreReassigned ||
        _platformFilter == null ||
        _isSearchMode) {
      print(
          'Skipping loadMoreReassignedTickets: hasMore=$_hasMoreReassigned, loading=$_isLoadingMoreReassigned, platformFilter=$_platformFilter, searchMode=$_isSearchMode');
      return;
    }

    setState(() => _isLoadingMoreReassigned = true);

    try {
      // Query reassigned_tickets to get ticket IDs
      var reassignedQuery = firestore
          .collection('reassigned_tickets')
          .where('newAgentId', isNull: true)
          .orderBy('timestamp', descending: true);

      if (_lastReassignedDocument != null) {
        reassignedQuery = reassignedQuery.startAfterDocument(_lastReassignedDocument!);
      }

      reassignedQuery = reassignedQuery.limit(_pageSize);

      final reassignedSnapshot = await reassignedQuery.get();
      print('Found ${reassignedSnapshot.docs.length} reassigned tickets');
      if (reassignedSnapshot.docs.isEmpty) {
        setState(() => _hasMoreReassigned = false);
        setState(() => _isLoadingMoreReassigned = false);
        return;
      }

      // Extract ticket IDs and split into batches of 10 (Firestore whereIn limit)
      final ticketIds =
      reassignedSnapshot.docs.map((doc) => doc['ticketId'] as String).toList();
      print('Ticket IDs: $ticketIds');
      const batchSize = 10;
      final List<Ticket> newTickets = [];

      for (var i = 0; i < ticketIds.length; i += batchSize) {
        final batch = ticketIds.sublist(
            i, i + batchSize > ticketIds.length ? ticketIds.length : i + batchSize);
        print('Fetching tickets for batch: $batch');

        var ticketsQuery = firestore
            .collection('tickets')
            .where('platform', isEqualTo: _platformFilter)
            .where('reassigned', isEqualTo: true)
            .where(FieldPath.documentId, whereIn: batch)
            .orderBy('createdAt', descending: true);

        final ticketsSnapshot = await ticketsQuery.get();
        print('Fetched ${ticketsSnapshot.docs.length} tickets for batch');

        newTickets.addAll(
          ticketsSnapshot.docs
              .map(Ticket.fromFirestore)
              .where((ticket) => ticket.assignedTo == null)
              .toList(),
        );
      }

      print('Total new tickets after filtering: ${newTickets.length}');
      if (newTickets.isEmpty) {
        setState(() => _hasMoreReassigned = false);
      } else {
        _lastReassignedDocument = reassignedSnapshot.docs.last;
        setState(() => _reassignedTickets = [..._reassignedTickets, ...newTickets]);
      }
    } catch (e) {
      print('Error loading reassigned tickets: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading reassigned tickets: $e')),
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
    if (!_hasMorePlatform ||
        _isLoadingMorePlatform ||
        _platformFilter == null ||
        _isSearchMode) {
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
        SnackBar(content: Text('Error loading platform tickets: $e')),
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
      // Search reassigned tickets
      var reassignedTitleQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: true)
          .orderBy('title')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        reassignedTitleQuery =
            reassignedTitleQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        reassignedTitleQuery =
            reassignedTitleQuery.where('priority', isEqualTo: _priorityFilter);
      }

      var reassignedDescQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: true)
          .orderBy('description')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        reassignedDescQuery =
            reassignedDescQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        reassignedDescQuery =
            reassignedDescQuery.where('priority', isEqualTo: _priorityFilter);
      }

      // Search platform tickets (non-reassigned)
      var platformTitleQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: false)
          .orderBy('title')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        platformTitleQuery =
            platformTitleQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        platformTitleQuery =
            platformTitleQuery.where('priority', isEqualTo: _priorityFilter);
      }

      var platformDescQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .where('reassigned', isEqualTo: false)
          .orderBy('description')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        platformDescQuery =
            platformDescQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        platformDescQuery =
            platformDescQuery.where('priority', isEqualTo: _priorityFilter);
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
        SnackBar(content: Text('Error searching tickets: $e')),
      );
    } finally {
      setState(() => _isLoadingSearch = false);
    }
  }

  Future<void> _updateTicketStatus(String ticketId, String newStatus) async {
    try {
      await firestore.collection('tickets').doc(ticketId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _loadInitialReassignedTickets();
      _loadInitialPlatformTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket status updated!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating ticket: $e')),
      );
    }
  }

  Future<void> _assignTicket(String ticketId, String newAgentId) async {
    try {
      // Verify the user's role
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      final userRole = userDoc.data()!['role'] as String? ?? 'unknown';
      print('Assigning ticket: user role=$userRole');
      if (userRole != 'moderator') {
        throw Exception('Only moderators can assign tickets to agents');
      }

      // Fetch the ticket to get platform, priority, and status
      final ticketDoc = await firestore.collection('tickets').doc(ticketId).get();
      if (!ticketDoc.exists) {
        throw Exception('Ticket not found');
      }
      final ticketData = ticketDoc.data()! as Map<String, dynamic>;
      final ticketPlatform = ticketData['platform'] as String;
      final currentPriority = ticketData['priority'] as String;
      final currentStatus = ticketData['status'] as String;

      print('Ticket platform: $ticketPlatform, Moderator platform: $_platformFilter');
      if (ticketPlatform != _platformFilter) {
        throw Exception('Platform mismatch: Ticket platform ($ticketPlatform) does not match moderator platform ($_platformFilter)');
      }

      // Run a transaction to update both tickets and reassigned_tickets atomically
      await firestore.runTransaction((transaction) async {
        // Update the ticket
        final ticketRef = firestore.collection('tickets').doc(ticketId);
        transaction.update(ticketRef, {
          'assignedTo': newAgentId,
          'priority': currentPriority,
          'status': currentStatus,
          'reassigned': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update the reassigned_tickets entry
        final reassignedDocs = await firestore
            .collection('reassigned_tickets')
            .where('ticketId', isEqualTo: ticketId)
            .where('newAgentId', isNull: true)
            .get();
        if (reassignedDocs.docs.isEmpty) {
          throw Exception('No pending reassignment found for this ticket');
        }
        for (var doc in reassignedDocs.docs) {
          print('Updating reassigned_tickets document: ${doc.id}');
          transaction.update(doc.reference, {
            'newAgentId': newAgentId,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      });

      await _loadInitialReassignedTickets();
      await _loadInitialPlatformTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket assigned!')),
      );
    } catch (e) {
      print('Error assigning ticket: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error assigning ticket: $e')),
      );
    }
  }

  void _showTicketOptions(BuildContext context, Ticket ticket) {
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
                  _showStatusChangeDialog(context, ticket);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Assign Ticket'),
                onTap: () {
                  Navigator.pop(context);
                  _showAssignDialog(context, ticket);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat),
                title: const Text('Add Response'),
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
          title: const Text('Change Ticket Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Open'),
                leading: const Icon(Icons.circle, color: Colors.orange),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus(ticket.id, 'open');
                },
              ),
              ListTile(
                title: const Text('In Progress'),
                leading: const Icon(Icons.circle, color: Colors.blue),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus(ticket.id, 'in_progress');
                },
              ),
              ListTile(
                title: const Text('Resolved'),
                leading: const Icon(Icons.circle, color: Colors.green),
                onTap: () {
                  Navigator.pop(context);
                  _updateTicketStatus(ticket.id, 'resolved');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAssignDialog(BuildContext context, Ticket ticket) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Assign Ticket'),
          content: FutureBuilder<QuerySnapshot>(
            future: firestore
                .collection('users')
                .where('role', isEqualTo: 'agent')
                .where('platform', isEqualTo: _platformFilter)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
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
                      title: Text(agentName),
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderator Dashboard'),
        actions: [
          IconButton(
            icon: Icon(_isSearchMode ? Icons.cancel : Icons.search),
            onPressed: () {
              setState(() {
                _isSearchMode = !_isSearchMode;
                if (!_isSearchMode) {
                  _searchQuery = '';
                  _searchTickets('');
                }
              });
            },
          ),
          _buildFilterMenu(),
          IconButton(
            icon: const Icon(Icons.refresh),
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
      body: Column(
        children: [
          if (_isSearchMode)
            Padding(
              padding: const EdgeInsets.all(8.0),
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
          Expanded(
            child: Stack(
              children: [
                _platformFilter == null
                    ? const Center(
                  child: Text(
                    'Platform not set. Please complete your profile.',
                    textAlign: TextAlign.center,
                  ),
                )
                    : _buildTicketList(),
                if (_isLoadingSearch)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_alt),
      onSelected: (value) {
        if (value == 'filter') {
          _showFilterDialog();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'filter',
          child: Row(
            children: const [
              Icon(Icons.filter_alt),
              SizedBox(width: 8),
              Text('Filter Tickets'),
            ],
          ),
        ),
      ],
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Filter Tickets'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: _filterStatus,
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Statuses'),
                      ),
                      DropdownMenuItem(
                        value: 'open',
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.orange, size: 16),
                            SizedBox(width: 8),
                            Text('Open'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'in_progress',
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.blue, size: 16),
                            SizedBox(width: 8),
                            Text('In Progress'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'resolved',
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.green, size: 16),
                            SizedBox(width: 8),
                            Text('Resolved'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _filterStatus = value!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _priorityFilter,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Priorities'),
                      ),
                      DropdownMenuItem(
                        value: 'low',
                        child: Row(
                          children: const [
                            Icon(Icons.flag, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Low'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'medium',
                        child: Row(
                          children: const [
                            Icon(Icons.flag, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Medium'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'high',
                        child: Row(
                          children: const [
                            Icon(Icons.flag, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('High'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'critical',
                        child: Row(
                          children: const [
                            Icon(Icons.flag, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Critical'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _priorityFilter = value),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (_isSearchMode) {
                      _searchTickets(_searchQuery);
                    } else {
                      _loadInitialReassignedTickets();
                      _loadInitialPlatformTickets();
                    }
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTicketList() {
    final allTickets = [..._reassignedTickets, ..._platformTickets];
    if (allTickets.isEmpty &&
        !_isLoadingMoreReassigned &&
        !_isLoadingMorePlatform &&
        !_isLoadingSearch) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_isSearchMode
                ? 'No tickets match your search'
                : 'No tickets found in your platform'),
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
                child: const Text('Clear filters'),
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
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: allTickets.length +
            (_hasMoreReassigned && _isLoadingMoreReassigned && !_isSearchMode ? 1 : 0) +
            (_hasMorePlatform && _isLoadingMorePlatform && !_isSearchMode ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= allTickets.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final ticket = allTickets[index];
          final isReassigned = _reassignedTickets.contains(ticket);
          return _buildTicketCard(ticket, isReassigned);
        },
      ),
    );
  }

  Widget _buildTicketCard(Ticket ticket, bool isReassigned) {
    return GestureDetector(
      onLongPress: () => _showTicketOptions(context, ticket),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _viewTicketDetails(context, ticket.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isReassigned)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Chip(
                                label: Text(
                                  'Reassigned',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                backgroundColor: Colors.red,
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM dd, yyyy').format(ticket.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                if (ticket.assignedTo != null) ...[
                  const SizedBox(height: 4),
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
                        return Text(
                          'Assigned to: $agentName',
                          style: const TextStyle(fontSize: 12),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ],
                if (ticket.platform != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Platform: ${ticket.platform}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (ticket.equipment != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Equipment: ${ticket.equipment}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                if (ticket.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    ticket.description,
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
      'low': const Icon(Icons.flag, color: Colors.green),
      'medium': const Icon(Icons.flag, color: Colors.blue),
      'high': const Icon(Icons.flag, color: Colors.orange),
      'critical': const Icon(Icons.flag, color: Colors.red),
    };
    return Tooltip(
      message: priority.toUpperCase(),
      child: priorityData[priority] ?? const Icon(Icons.flag),
    );
  }

  Widget _buildStatusChip(String status) {
    final statusColors = {
      'open': Colors.orange,
      'in_progress': Colors.blue,
      'resolved': Colors.green,
      'closed': Colors.grey,
    };

    return Chip(
      label: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: statusColors[status] ?? Colors.grey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  void _viewTicketDetails(BuildContext context, String ticketId,
      {bool initialFocusResponse = false}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TicketDetailsScreen(
          ticketId: ticketId,
          isAgent: true,
          initialFocusResponse: initialFocusResponse,
        ),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ticket updated!'),
          duration: Duration(seconds: 2),
        ),
      );
      _loadInitialReassignedTickets();
      _loadInitialPlatformTickets();
    }
  }
}