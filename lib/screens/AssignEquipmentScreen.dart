import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

class AssignEquipmentScreen extends StatefulWidget {
  const AssignEquipmentScreen({Key? key}) : super(key: key);

  @override
  _AssignEquipmentScreenState createState() => _AssignEquipmentScreenState();
}

class _AssignEquipmentScreenState extends State<AssignEquipmentScreen> {
  String? _selectedPlatform;
  List<String> _equipmentList = [];
  List<Map<String, dynamic>> _agents = [];
  bool _isLoading = false;
  bool _isLoadingPlatform = true;

  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadModeratorPlatform();
  }

  Future<void> _loadModeratorPlatform() async {
    setState(() => _isLoadingPlatform = true);
    try {
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      final role = userDoc['role'] as String?;
      final platform = userDoc['platform'] as String?;
      if (role != 'moderator') {
        throw Exception('User is not a moderator: role=$role');
      }
      if (platform == null || platform.trim().isEmpty) {
        throw Exception('Moderator platform not set');
      }
      setState(() {
        _selectedPlatform = platform.trim();
        _isLoadingPlatform = false;
      });
      await Future.wait([
        _loadEquipmentForPlatform(_selectedPlatform!),
        _loadAgentsWithAssignments(_selectedPlatform!),
      ]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading platform: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      setState(() => _isLoadingPlatform = false);
    }
  }

  Future<void> _loadEquipmentForPlatform(String platform) async {
    setState(() => _isLoading = true);
    try {
      final platformsSnapshot = await firestore.collection('platforms').get();
      String? platformId;
      for (var doc in platformsSnapshot.docs) {
        if (doc.data()['designation'] == platform) {
          platformId = doc.id;
          break;
        }
      }
      if (platformId == null) throw Exception('Platform not found in Firestore');

      final equipmentSnapshot = await firestore.collection('platforms/$platformId/equipment').get();
      setState(() {
        _equipmentList = equipmentSnapshot.docs.map((doc) => doc.data()['designation'] as String).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load equipment: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAgentsWithAssignments(String platform) async {
    setState(() => _isLoading = true);
    try {
      final agentsSnapshot = await firestore
          .collection('users')
          .where('role', isEqualTo: 'agent')
          .where('platform', isEqualTo: platform)
          .get();

      final assignmentsSnapshot = await firestore
          .collection('equipment_assignments')
          .where('platform', isEqualTo: platform)
          .get();

      final assignmentsMap = {
        for (var doc in assignmentsSnapshot.docs)
          doc['agentId'] as String: {
            'docId': doc.id,
            'equipment': (doc['equipment'] as List<dynamic>)
                .map((item) => item?.toString() ?? '')
                .where((item) => item.isNotEmpty)
                .toList() as List<String>,
          }
      };

      setState(() {
        _agents = agentsSnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final agentId = doc.id;
          final assignment = assignmentsMap[agentId];
          return {
            'id': agentId,
            'name': data['fullName'] ?? 'Agent $agentId',
            'equipment': assignment != null ? assignment['equipment'] : <String>[],
            'assignmentDocId': assignment != null ? assignment['docId'] : null,
          };
        }).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load agents: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editAgentEquipment(String agentId, String? assignmentDocId, List<String> currentEquipment) async {
    List<String> selectedEquipment = List.from(currentEquipment);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(
                'Edit Equipment',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _equipmentList.map((equipment) {
                    return CheckboxListTile(
                      title: Text(
                        equipment,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      activeColor: Theme.of(context).colorScheme.primary,
                      value: selectedEquipment.contains(equipment),
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            selectedEquipment.add(equipment);
                          } else {
                            selectedEquipment.remove(equipment);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;

    setState(() => _isLoading = true);
    try {
      selectedEquipment = selectedEquipment.toSet().toList();

      if (selectedEquipment.isEmpty && assignmentDocId != null) {
        await firestore.collection('equipment_assignments').doc(assignmentDocId).delete();
        setState(() {
          final agentIndex = _agents.indexWhere((agent) => agent['id'] == agentId);
          _agents[agentIndex]['equipment'] = <String>[];
          _agents[agentIndex]['assignmentDocId'] = null;
        });
      } else if (assignmentDocId != null) {
        await firestore.collection('equipment_assignments').doc(assignmentDocId).update({
          'equipment': selectedEquipment,
          'assignedAt': FieldValue.serverTimestamp(),
        });
        setState(() {
          final agentIndex = _agents.indexWhere((agent) => agent['id'] == agentId);
          _agents[agentIndex]['equipment'] = selectedEquipment;
        });
      } else if (selectedEquipment.isNotEmpty) {
        final newDocRef = await firestore.collection('equipment_assignments').add({
          'agentId': agentId,
          'equipment': selectedEquipment,
          'assignedBy': userId,
          'assignedAt': FieldValue.serverTimestamp(),
          'platform': _selectedPlatform,
        });
        setState(() {
          final agentIndex = _agents.indexWhere((agent) => agent['id'] == agentId);
          _agents[agentIndex]['equipment'] = selectedEquipment;
          _agents[agentIndex]['assignmentDocId'] = newDocRef.id;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Equipment updated successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating equipment: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: MediaQuery.of(context).size.height,
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
        child: Column(
          children: [
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading || _isLoadingPlatform
            ? null
            : () async {
          setState(() => _isLoading = true);
          await _loadModeratorPlatform();
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          Icons.refresh,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        tooltip: 'Refresh',
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoadingPlatform) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
        ),
      );
    }

    if (_selectedPlatform == null) {
      return Center(
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
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return AnimationLimiter(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 375),
            childAnimationBuilder: (widget) => SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(child: widget),
            ),
            children: [
              Text(
                'Platform: $_selectedPlatform',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                  ),
                )
              else if (_agents.isEmpty)
                Center(
                  child: Text(
                    'No agents found for this platform.',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                _buildAgentsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agents',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _agents.length,
          itemBuilder: (context, index) {
            final agent = _agents[index];
            final equipment = agent['equipment'] as List<String>;
            return AnimationConfiguration.staggeredList(
              position: index,
              duration: const Duration(milliseconds: 375),
              child: SlideAnimation(
                verticalOffset: 50.0,
                child: FadeInAnimation(
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(
                        agent['name'],
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: equipment.isNotEmpty
                          ? Text(
                        'Equipment: ${equipment.join(', ')}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                          : Text(
                        'No equipment assigned',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.edit,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        onPressed: () => _editAgentEquipment(
                          agent['id'],
                          agent['assignmentDocId'],
                          equipment,
                        ),
                        tooltip: 'Edit Equipment',
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}