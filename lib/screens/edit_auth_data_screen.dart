import 'package:flutter/material.dart';

class EditAuthDataScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Authentication Data'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextFormField(
              obscureText: true,
              decoration: InputDecoration(labelText: 'Current Password'),
            ),
            SizedBox(height: 20),
            TextFormField(
              obscureText: true,
              decoration: InputDecoration(labelText: 'New Password'),
            ),
            SizedBox(height: 20),
            TextFormField(
              obscureText: true,
              decoration: InputDecoration(labelText: 'Confirm New Password'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Save authentication changes
              },
              child: Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}