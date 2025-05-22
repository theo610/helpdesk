import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../models/ticket_model.dart';
import 'create_ticket_screen.dart';
import 'ticketDetailsScreen.dart';

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

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({Key? key}) : super(key: key);

  @override
  _EmployeeDashboardState createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> with SingleTickerProviderStateMixin {
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final int _pageSize = 15;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isLoadingSearch = false;
  bool _isSearchMode = false;

  String _filterStatus = 'all';
  String? _priorityFilter;
  String _searchQuery = '';

  List<Ticket> _tickets = [];
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
    _loadInitialTickets();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dialogAnimationController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent &&
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
        SnackBar(
          content: Text('Error loading tickets: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
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
        SnackBar(
          content: Text('Error searching tickets: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoadingSearch = false);
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
                  'Edit Ticket',
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _editTicket(context, ticket);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                title: Text(
                  'Delete Ticket',
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 16,
                  ),
                ),
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
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CreateTicketScreen(ticket: ticket),
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
      _loadInitialTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket updated successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  Future<void> _confirmDeleteTicket(BuildContext context, Ticket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Ticket',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this ticket?',
          style: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.error),
            ),
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
      if (ticket.status == 'in_progress') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You cannot delete a ticket that is in progress',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      await firestore.collection('tickets').doc(ticket.id).delete();
      _loadInitialTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket deleted successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Error deleting ticket: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting ticket: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
          child: Column(
            children: [
              _buildHeader(),
              if (_isSearchMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
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
            ],
          ),
        ),
      ),
      floatingActionButton: Semantics(
        label: 'Create new ticket',
        child: FloatingActionButton(
          onPressed: () => _createNewTicket(context),
          child: Icon(
            Icons.add,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          tooltip: 'Create Ticket',
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'My Tickets',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onBackground,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isSearchMode ? Icons.cancel : Icons.search,
                  color: Theme.of(context).colorScheme.primary,
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
                ),
                onPressed: _isSearchMode ? null : _loadInitialTickets,
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
                        _loadInitialTickets();
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

  Widget _buildTicketList() {
    if (_tickets.isEmpty && !_isLoadingMore && !_isLoadingSearch) {
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
              _isSearchMode ? 'No tickets match your search' : 'No tickets found',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
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
                    _loadInitialTickets();
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
            if (!_isSearchMode)
              TextButton(
                onPressed: () => _createNewTicket(context),
                child: Text(
                  'Create your first ticket',
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
      onRefresh: _isSearchMode ? () => _searchTickets(_searchQuery) : _loadInitialTickets,
      child: AnimationLimiter(
        child: ListView.builder(
          key: const Key('ticketList'), // Forces rebuild to trigger animation
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: _tickets.length + (_hasMore && _isLoadingMore && !_isSearchMode ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _tickets.length) {
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
            return AnimationConfiguration.staggeredList(
              position: index,
              duration: const Duration(milliseconds: 375),
              child: SlideAnimation(
                verticalOffset: 50.0,
                child: FadeInAnimation(
                  child: _buildTicketCard(_tickets[index]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTicketCard(Ticket ticket) {
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
                if (ticket.assignedTo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FutureBuilder<DocumentSnapshot>(
                            future: firestore.collection('users').doc(ticket.assignedTo).get(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return Text(
                                  'Loading agent...',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                );
                              }
                              if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                                return Text(
                                  'Unknown Agent',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                );
                              }
                              final user = snapshot.data!;
                              final userData = user.data() as Map<String, dynamic>?;
                              final agentName = userData != null &&
                                  userData.containsKey('fullName') &&
                                  userData['fullName'] != null
                                  ? userData['fullName']
                                  : 'Agent ${user.id}';
                              return Text(
                                'Assigned to: $agentName',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              );
                            },
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

  void _createNewTicket(BuildContext context) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CreateTicketScreen(),
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
          content: Text('Ticket created successfully!', style: GoogleFonts.poppins()),
          duration: Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      _loadInitialTickets();
    }
  }

  void _viewTicketDetails(BuildContext context, String ticketId) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => TicketDetailsScreen(
          ticketId: ticketId,
          isEmployee: true,
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
      _loadInitialTickets();
    }
  }
}