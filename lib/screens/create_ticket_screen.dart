import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ticket_model.dart';

class CreateTicketScreen extends StatefulWidget {
  final Ticket? ticket;

  const CreateTicketScreen({Key? key, this.ticket}) : super(key: key);

  @override
  _CreateTicketScreenState createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  String _selectedPriority = 'medium';
  String? _selectedPlatform;
  String? _selectedEquipment;
  List<String> _platforms = [];
  Map<String, List<String>> _equipmentMap = {};
  Map<String, String> _platformIdMap = {};
  final List<String> _priorities = ['low', 'medium', 'high', 'critical'];

  @override
  void initState() {
    super.initState();
    if (widget.ticket != null) {
      _titleController.text = widget.ticket!.title;
      _descriptionController.text = widget.ticket!.description;
      _selectedPriority = widget.ticket!.priority.toString().split('.').last;
      _selectedPlatform = widget.ticket!.platform;
      _selectedEquipment = widget.ticket!.equipment;
    }
    _loadPlatforms();
  }

  Future<void> _loadPlatforms() async {
    try {
      final platformsSnapshot = await FirebaseFirestore.instance.collection('platforms').get();
      setState(() {
        for (var doc in platformsSnapshot.docs) {
          String designation = doc.data()['designation'] as String;
          _platforms.add(designation);
          _platformIdMap[designation] = doc.id;
        }
      });
      if (_selectedPlatform != null) {
        await _loadEquipmentForPlatform(_selectedPlatform!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load platforms: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadEquipmentForPlatform(String platform) async {
    try {
      final platformId = _platformIdMap[platform];
      if (platformId == null) return;
      final equipmentSnapshot = await FirebaseFirestore.instance
          .collection('platforms/$platformId/equipment')
          .get();
      setState(() {
        _equipmentMap[platform] = equipmentSnapshot.docs
            .map((doc) => doc.data()['designation'] as String)
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load equipment: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ticket == null ? 'Create New Ticket' : 'Edit Ticket'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                readOnly: widget.ticket != null, // Prevent editing title
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedPriority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                ),
                items: _priorities.map((priority) {
                  return DropdownMenuItem<String>(
                    value: priority,
                    child: Row(
                      children: [
                        _getPriorityIcon(priority),
                        const SizedBox(width: 10),
                        Text(priority[0].toUpperCase() + priority.substring(1)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPriority = value!;
                  });
                },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedPlatform,
                decoration: const InputDecoration(
                  labelText: 'Platform',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Select platform'),
                isExpanded: true,
                items: _platforms.map((platform) {
                  return DropdownMenuItem<String>(
                    value: platform,
                    child: Text(
                      platform,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) async {
                  setState(() {
                    _selectedPlatform = value;
                    _selectedEquipment = null;
                    _equipmentMap[value!] = [];
                  });
                  await _loadEquipmentForPlatform(value!);
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a platform';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              if (_selectedPlatform != null && _equipmentMap[_selectedPlatform]?.isNotEmpty == true)
                DropdownButtonFormField<String>(
                  value: _selectedEquipment,
                  decoration: const InputDecoration(
                    labelText: 'Equipment (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Select equipment (optional)'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('None'),
                    ),
                    ..._equipmentMap[_selectedPlatform!]!.map((equipment) {
                      return DropdownMenuItem<String>(
                        value: equipment,
                        child: Text(
                          equipment,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedEquipment = value;
                    });
                  },
                ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _isSubmitting ? null : _submitTicket,
                child: _isSubmitting
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : Text(
                  widget.ticket == null ? 'Submit Ticket' : 'Update Ticket',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getPriorityIcon(String priority) {
    switch (priority) {
      case 'low':
        return const Icon(Icons.flag, color: Colors.green, size: 20);
      case 'medium':
        return const Icon(Icons.flag, color: Colors.blue, size: 20);
      case 'high':
        return const Icon(Icons.flag, color: Colors.orange, size: 20);
      case 'critical':
        return const Icon(Icons.flag, color: Colors.red, size: 20);
      default:
        return const Icon(Icons.flag, size: 20);
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Fetch the current user's name
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!userDoc.exists) {
        throw Exception('User data not found');
      }
      final userData = userDoc.data() ?? {};
      final userName = userData['nickName'] as String? ?? userData['fullName'] as String? ?? 'Unknown';

      // Normalize platform to lowercase
      final normalizedPlatform = _selectedPlatform!;

      // Use the Ticket model to construct the ticket data
      if (widget.ticket == null) {
        // Create a new ticket
        final newTicket = Ticket(
          id: '', // ID will be set by Firestore
          title: _titleController.text,
          description: _descriptionController.text,
          status: 'open',
          priority: _selectedPriority,
          platform: normalizedPlatform,
          platformName: normalizedPlatform, // Set platformName to match platform
          equipment: _selectedEquipment,
          equipmentName: _selectedEquipment, // Set equipmentName to match equipment
          createdBy: user.uid,
          createdByName: userName,
          createdAt: DateTime.now(), // Will be overridden by serverTimestamp
          updatedAt: DateTime.now(), // Will be overridden by serverTimestamp
          assignedTo: null,
          reassigned: false,
        );

        // Convert to Firestore data, overriding timestamps
        final ticketData = newTicket.toFirestore()
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp();

        print('Creating ticket with data: $ticketData'); // Debug log

        await FirebaseFirestore.instance.collection('tickets').add(ticketData);
      } else {
        // Update an existing ticket
        final ticketData = <String, dynamic>{
          'description': _descriptionController.text,
          'priority': _selectedPriority,
          'platform': normalizedPlatform,
          'platformName': normalizedPlatform,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Only include equipment fields if an equipment is selected
        if (_selectedEquipment != null) {
          ticketData['equipment'] = _selectedEquipment;
          ticketData['equipmentName'] = _selectedEquipment;
        } else {
          ticketData.remove('equipment');
          ticketData.remove('equipmentName');
        }

        print('Updating ticket with data: $ticketData'); // Debug log

        await FirebaseFirestore.instance
            .collection('tickets')
            .doc(widget.ticket!.id)
            .update(ticketData);
      }

      Navigator.pop(context, true);
    } catch (e) {
      String errorMessage;
      if (e.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied: You may not have the necessary role to perform this action.';
      } else if (e.toString().contains('network')) {
        errorMessage = 'Network error: Please check your internet connection and try again.';
      } else {
        errorMessage = 'Error: ${e.toString()}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}