import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final String userId;

  const ProfileDetailsScreen({required this.userId, Key? key}) : super(key: key);

  @override
  _ProfileDetailsScreenState createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  String _selectedRole = 'employee';
  String? _selectedPlatform;
  List<String> _platforms = [];
  bool _isLoading = false;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _loadPlatforms();
  }

  Future<void> _fetchUserData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data();
          _selectedRole = _userData!['role'] ?? 'employee';
          _selectedPlatform = _userData!['platform'];
        });
      }
    } catch (e) {
      print('Error fetching user data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching user data: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadPlatforms() async {
    try {
      final platformsSnapshot =
      await FirebaseFirestore.instance.collection('platforms').get();
      setState(() {
        _platforms = platformsSnapshot.docs
            .map((doc) => doc.data()['designation'] as String)
            .toList();
      });
    } catch (e) {
      print('Error loading platforms: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load platforms: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _approveProfile() async {
    try {
      setState(() => _isLoading = true);
      final updateData = {
        'isApproved': true,
        'role': _selectedRole,
        'isActive': true,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (_selectedRole == 'agent' || _selectedRole == 'moderator') {
        if (_selectedPlatform == null || _selectedPlatform!.isEmpty) {
          throw Exception('Platform is required for agent or moderator roles');
        }
        updateData['platform'] = _selectedPlatform!; // Use ! to assert non-null
      } else if (_selectedRole == 'employee') {
        updateData['platform'] = FieldValue.delete(); // Remove platform for employee role
      }

      print('Approving profile with data: $updateData');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(updateData);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile approved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      print('Error approving profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error approving profile: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _denyProfile() async {
    try {
      setState(() => _isLoading = true);
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (userDoc.exists) {
        await FirebaseFirestore.instance
            .collection('denied_users')
            .doc(widget.userId)
            .set({
          ...userDoc.data()!,
          'status': 'Denied',
          'deniedAt': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .delete();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile denied and deleted.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error denying profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error denying profile: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Details'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 60,
              backgroundImage: _userData!['profileImageUrl'] != null
                  ? NetworkImage(_userData!['profileImageUrl'])
                  : const AssetImage('assets/default_profile.png') as ImageProvider,
              backgroundColor: Colors.grey[200],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: TextEditingController(text: _userData!['fullName']),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _userData!['nickName']),
              decoration: const InputDecoration(
                labelText: 'Nickname',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.face),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _userData!['email']),
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _userData!['phoneNumber']),
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _userData!['address']),
              decoration: const InputDecoration(
                labelText: 'Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.home),
              ),
              readOnly: true,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _userData!['country']),
              decoration: const InputDecoration(
                labelText: 'Country',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _userData!['gender']),
              decoration: const InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.transgender),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'User Role',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.work),
              ),
              items: const [
                DropdownMenuItem(value: 'employee', child: Text('Employee')),
                DropdownMenuItem(value: 'agent', child: Text('Agent')),
                DropdownMenuItem(value: 'moderator', child: Text('Moderator')),
              ],
              onChanged: (String? newValue) {
                setState(() {
                  _selectedRole = newValue!;
                  if (_selectedRole == 'employee') {
                    _selectedPlatform = null;
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            if (_selectedRole == 'agent' || _selectedRole == 'moderator')
              DropdownButtonFormField<String>(
                value: _selectedPlatform,
                decoration: const InputDecoration(
                  labelText: 'Platform',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.build),
                ),
                hint: const Text('Select Platform'),
                items: _platforms
                    .map((platform) => DropdownMenuItem(
                  value: platform,
                  child: Text(platform),
                ))
                    .toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedPlatform = newValue;
                  });
                },
                validator: (value) {
                  if ((_selectedRole == 'agent' || _selectedRole == 'moderator') &&
                      value == null) {
                    return 'Please select a platform';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SizedBox(
                  width: 150,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _approveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      'Approve',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _denyProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      'Deny',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}