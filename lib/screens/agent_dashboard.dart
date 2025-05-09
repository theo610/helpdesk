import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/ticket_model.dart';
import 'ticketDetailsScreen.dart';
import '../models/response_model.dart';

// Reusing the SearchBar widget
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

class AgentDashboard extends StatefulWidget {
  const AgentDashboard({Key? key}) : super(key: key);

  @override
  _AgentDashboardState createState() => _AgentDashboardState();
}

class _AgentDashboardState extends State<AgentDashboard> {
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final int _pageSize = 15;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isLoadingSearch = false;
  bool _isSearchMode = false;

  String _filterStatus = 'all';
  String _searchQuery = '';
  String? _priorityFilter;
  String? _platformFilter;
  bool? _reassignedFilter; // Add reassigned filter

  List<Ticket> _tickets = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadAgentPlatform().then((_) => _loadInitialTickets());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAgentPlatform() async {
    try {
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      var role = userDoc['role'] as String?;
      var platform = userDoc['platform'] as String?;
      print('Agent role: $role, platform: $platform');
      if (role == null || !['agent', 'moderator'].contains(role)) {
        throw Exception('User is not an agent or moderator: role=$role');
      }
      if (platform != null) {
        platform = platform;
        print('Agent platform (normalized): $platform');
        setState(() => _platformFilter = platform);
      } else {
        throw Exception('Agent platform not set');
      }
    } catch (e) {
      print('Error loading agent platform: $e');
      setState(() => _platformFilter = null);
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent &&
        _hasMore &&
        !_isLoadingMore &&
        !_isSearchMode) {
      _loadMoreTickets();
    }
  }

  Future<void> _loadInitialTickets() async {
    setState(() {
      _tickets = [];
      _lastDocument = null;
      _hasMore = true;
      _isLoadingMore = false;
    });
    await _loadMoreTickets();
  }

  Future<void> _loadMoreTickets() async {
    if (!_hasMore || _isLoadingMore || _platformFilter == null || _isSearchMode) {
      print(
          'Skipping load: hasMore=$_hasMore, isLoadingMore=$_isLoadingMore, platformFilter=$_platformFilter, isSearchMode=$_isSearchMode');
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      print('Fetching tickets for platform: $_platformFilter');
      var query = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .orderBy('createdAt', descending: true);

      if (_filterStatus != 'all') {
        query = query.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        final priorityString = _priorityFilter!.toLowerCase();
        query = query.where('priority', isEqualTo: priorityString);
      }
      if (_reassignedFilter != null) {
        query = query.where('reassigned', isEqualTo: _reassignedFilter);
      }

      query = query.limit(_pageSize);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();
      print('Fetched ${snapshot.docs.length} tickets for platform: $_platformFilter');
      snapshot.docs.forEach((doc) {
        print('Ticket platform: ${doc['platform']}');
      });

      if (snapshot.docs.isEmpty) {
        setState(() => _hasMore = false);
      } else {
        _lastDocument = snapshot.docs.last;
        setState(() => _tickets = [
          ..._tickets,
          ...snapshot.docs.map(Ticket.fromFirestore),
        ]);
      }
    } catch (e) {
      print('Error loading tickets: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading tickets: $e')),
      );
    } finally {
      setState(() => _isLoadingMore = false);
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
      await _loadInitialTickets();
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
      _tickets = [];
      _hasMore = false;
    });

    try {
      var titleQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .orderBy('title')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        titleQuery = titleQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        titleQuery = titleQuery.where('priority', isEqualTo: _priorityFilter);
      }
      if (_reassignedFilter != null) {
        titleQuery = titleQuery.where('reassigned', isEqualTo: _reassignedFilter);
      }

      var descQuery = firestore
          .collection('tickets')
          .where('platform', isEqualTo: _platformFilter)
          .orderBy('description')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        descQuery = descQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        descQuery = descQuery.where('priority', isEqualTo: _priorityFilter);
      }
      if (_reassignedFilter != null) {
        descQuery = descQuery.where('reassigned', isEqualTo: _reassignedFilter);
      }

      final titleSnapshot = await titleQuery.get();
      final descSnapshot = await descQuery.get();

      final ticketDocs = <String, Ticket>{};
      for (var doc in titleSnapshot.docs) {
        ticketDocs[doc.id] = Ticket.fromFirestore(doc);
      }
      for (var doc in descSnapshot.docs) {
        ticketDocs[doc.id] = Ticket.fromFirestore(doc);
      }

      setState(() {
        _tickets = ticketDocs.values.toList()
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
      _loadInitialTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket status updated!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating ticket: $e')),
      );
    }
  }

  Future<void> _reassignTicket(
      String ticketId, {
        required String details,
        required bool toModerator,
      }) async {
    try {
      // Fetch the current ticket data to get priority and status
      final ticketDoc = await firestore.collection('tickets').doc(ticketId).get();
      if (!ticketDoc.exists) {
        throw Exception('Ticket not found');
      }
      final ticketData = ticketDoc.data() as Map<String, dynamic>;
      final currentPriority = ticketData['priority'] as String;
      final currentStatus = ticketData['status'] as String;

      // Update the ticket: unassign and mark as reassigned
      await firestore.collection('tickets').doc(ticketId).update({
        'assignedTo': null,
        'priority': currentPriority,
        'status': currentStatus,
        'reassigned': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create a reassigned_tickets entry
      await firestore.collection('reassigned_tickets').add({
        'ticketId': ticketId,
        'previousAgentId': ticketData['assignedTo'] ?? '',
        'newAgentId': null,
        'details': details,
        'reassignedBy': userId,
        'sentToModeratorBy': userId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _loadInitialTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket sent to moderator successfully!')),
      );
    } catch (e) {
      print('Error sending ticket to moderator: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending ticket to moderator: $e')),
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
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Send to Moderator'),
                onTap: () {
                  Navigator.pop(context);
                  _showReassignToModeratorDialog(context, ticket);
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

  void _showReassignToModeratorDialog(BuildContext context, Ticket ticket) {
    final TextEditingController _detailsController = TextEditingController();
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
                    controller: _detailsController,
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
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  _reassignTicket(
                    ticket.id,
                    details: _detailsController.text.trim(),
                    toModerator: true,
                  );
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Tickets'),
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
            onPressed: _isSearchMode ? null : _loadInitialTickets,
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<bool>(
                    value: _reassignedFilter,
                    decoration: const InputDecoration(labelText: 'Reassigned'),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('All Tickets'),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text('Reassigned'),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Not Reassigned'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _reassignedFilter = value),
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
                      _loadInitialTickets();
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
    if (_tickets.isEmpty && !_isLoadingMore && !_isLoadingSearch) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_isSearchMode
                ? 'No tickets match your search'
                : 'No tickets found in your platform'),
            if (_filterStatus != 'all' || _priorityFilter != null || _reassignedFilter != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _filterStatus = 'all';
                    _priorityFilter = null;
                    _reassignedFilter = null;
                  });
                  if (_isSearchMode) {
                    _searchTickets(_searchQuery);
                  } else {
                    _loadInitialTickets();
                  }
                },
                child: const Text('Clear filters'),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _isSearchMode ? () => _searchTickets(_searchQuery) : _loadInitialTickets,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _tickets.length + (_hasMore && _isLoadingMore && !_isSearchMode ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _tickets.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _buildTicketCard(_tickets[index]);
        },
      ),
    );
  }

  Widget _buildTicketCard(Ticket ticket) {
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
                          if (ticket.reassigned)
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
      _loadInitialTickets();
    }
  }
}