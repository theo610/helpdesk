import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManagePlatformsScreen extends StatefulWidget {
  const ManagePlatformsScreen({Key? key}) : super(key: key);

  @override
  _ManagePlatformsScreenState createState() => _ManagePlatformsScreenState();
}

class _ManagePlatformsScreenState extends State<ManagePlatformsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _platformController = TextEditingController();
  final TextEditingController _equipmentController = TextEditingController();
  String? _selectedPlatformId;
  bool _isLoading = false;

  List<Map<String, dynamic>> _platforms = [];
  Map<String, List<Map<String, dynamic>>> _equipmentMap = {};

  @override
  void initState() {
    super.initState();
    _loadPlatforms();
  }

  Future<void> _loadPlatforms() async {
    setState(() => _isLoading = true);
    try {
      final platformsSnapshot = await FirebaseFirestore.instance.collection('platforms').get();
      _platforms = platformsSnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'designation': doc.data()['designation'] as String,
        };
      }).toList();

      // Load equipment for each platform
      for (var platform in _platforms) {
        final equipmentSnapshot = await FirebaseFirestore.instance
            .collection('platforms/${platform['id']}/equipment')
            .get();
        _equipmentMap[platform['id']] = equipmentSnapshot.docs.map((doc) {
          return {
            'id': doc.id,
            'designation': doc.data()['designation'] as String,
          };
        }).toList();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load platforms: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addPlatform() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('platforms').add({
        'designation': _platformController.text.trim(),
      });
      _platformController.clear();
      _loadPlatforms(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Platform added successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding platform: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addEquipment(String platformId) async {
    if (_equipmentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Equipment name cannot be empty'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('platforms/$platformId/equipment')
          .add({
        'designation': _equipmentController.text.trim(),
      });
      _equipmentController.clear();
      _loadPlatforms(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Equipment added successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding equipment: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePlatform(String platformId) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('platforms').doc(platformId).delete();
      _loadPlatforms(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Platform deleted successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting platform: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEquipment(String platformId, String equipmentId) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('platforms/$platformId/equipment')
          .doc(equipmentId)
          .delete();
      _loadPlatforms(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Equipment deleted successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting equipment: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Platforms & Equipment'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _platformController,
                    decoration: const InputDecoration(
                      labelText: 'New Platform',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a platform name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _addPlatform,
                    child: const Text('Add Platform'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _platforms.length,
              itemBuilder: (context, index) {
                final platform = _platforms[index];
                final platformId = platform['id'] as String;
                final equipmentList = _equipmentMap[platformId] ?? [];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ExpansionTile(
                    title: Text(platform['designation']),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deletePlatform(platformId),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _equipmentController,
                              decoration: const InputDecoration(
                                labelText: 'New Equipment',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () => _addEquipment(platformId),
                              child: const Text('Add Equipment'),
                            ),
                            const SizedBox(height: 10),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: equipmentList.length,
                              itemBuilder: (context, equipIndex) {
                                final equipment = equipmentList[equipIndex];
                                return ListTile(
                                  title: Text(equipment['designation']),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteEquipment(platformId, equipment['id']),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _platformController.dispose();
    _equipmentController.dispose();
    super.dispose();
  }
}