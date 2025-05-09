import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/ticket_model.dart';
import 'create_ticket_screen.dart';
import 'ticketDetailsScreen.dart';

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

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({Key? key}) : super(key: key);

  @override
  _EmployeeDashboardState createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
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

  List<Ticket> _tickets = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadInitialTickets();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    if (!_hasMore || _isLoadingMore || _isSearchMode) return;

    setState(() => _isLoadingMore = true);

    try {
      var query = firestore
          .collection('tickets')
          .where('createdBy', isEqualTo: userId)
          .orderBy('createdAt', descending: true);

      if (_filterStatus != 'all') {
        query = query.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        query = query.where('priority', isEqualTo: _priorityFilter);
      }

      query = query.limit(_pageSize);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();
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

    setState(() {
      _isLoadingSearch = true;
      _isSearchMode = true;
      _tickets = [];
      _hasMore = false;
    });

    try {
      var titleQuery = firestore
          .collection('tickets')
          .where('createdBy', isEqualTo: userId)
          .orderBy('title')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        titleQuery = titleQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        titleQuery = titleQuery.where('priority', isEqualTo: _priorityFilter);
      }

      var descQuery = firestore
          .collection('tickets')
          .where('createdBy', isEqualTo: userId)
          .orderBy('description')
          .startAt([query.toLowerCase()])
          .endAt(['${query.toLowerCase()}\uf8ff']);

      if (_filterStatus != 'all') {
        descQuery = descQuery.where('status', isEqualTo: _filterStatus);
      }
      if (_priorityFilter != null) {
        descQuery = descQuery.where('priority', isEqualTo: _priorityFilter);
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
                title: const Text('Edit Ticket'),
                onTap: () {
                  Navigator.pop(context);
                  _editTicket(context, ticket);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Ticket',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteTicket(context, ticket);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editTicket(BuildContext context, Ticket ticket) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateTicketScreen(ticket: ticket),
      ),
    );

    if (result == true) {
      _loadInitialTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket updated successfully!')),
      );
    }
  }

  Future<void> _confirmDeleteTicket(BuildContext context, Ticket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Ticket'),
        content: const Text('Are you sure you want to delete this ticket?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteTicket(ticket);
    }
  }

  Future<void> _deleteTicket(Ticket ticket) async {
    try {
      // Check if the ticket is in progress
      if (ticket.status == 'in_progress') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot delete a ticket that is in progress')),
        );
        return;
      }

      // Delete the ticket
      await firestore.collection('tickets').doc(ticket.id).delete();
      _loadInitialTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket deleted successfully!')),
      );
    } catch (e) {
      print('Error deleting ticket: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting ticket: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
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
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _createNewTicket(context),
        tooltip: 'Create Ticket',
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
                _buildTicketList(),
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
                : 'No tickets found'),
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
                    _loadInitialTickets();
                  }
                },
                child: const Text('Clear filters'),
              ),
            if (!_isSearchMode)
              TextButton(
                onPressed: () => _createNewTicket(context),
                child: const Text('Create your first ticket'),
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
    // Note: Intentionally not displaying reassignment data (e.g., "Reassigned" chip or reassigned agent)
    // even if ticket.reassigned is true, as per requirements.
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
                      child: Text(
                        ticket.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 4),
                if (ticket.platform != null)
                  Text(
                    'Platform: ${ticket.platform}',
                    style: const TextStyle(fontSize: 12),
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

  void _createNewTicket(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateTicketScreen()),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ticket created successfully!'),
          duration: Duration(seconds: 2),
        ),
      );
      _loadInitialTickets();
    }
  }

  void _viewTicketDetails(BuildContext context, String ticketId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TicketDetailsScreen(
          ticketId: ticketId,
          isEmployee: true, // Indicate that the user is an employee
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