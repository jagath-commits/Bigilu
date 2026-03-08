import 'package:flutter/material.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Terms & Conditions"),
      ),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
"""
Welcome to Bigiluu.

By using the Bigiluu application you agree to the following terms and conditions.

1. Platform Usage
Bigiluu is a digital platform that allows users to publish, read, and share short books or posts. Users can create content and publish it for other readers.

2. User Content
Users are responsible for the content they publish. Content must not contain illegal, abusive, or copyrighted material without permission.

3. Account Responsibility
Users are responsible for maintaining the security of their account and any activity that occurs under their account.

4. Content Removal
Bigiluu reserves the right to remove any content that violates community guidelines or applicable laws.

5. Intellectual Property
Users retain ownership of the content they publish but grant Bigiluu permission to display and distribute the content within the platform.

6. Sharing
Users may share posts through the share feature, but the content must not be altered or misrepresented.

7. Service Changes
Bigiluu may update or modify the platform features at any time to improve user experience.

8. Limitation of Liability
Bigiluu is not responsible for any damages resulting from the use of the platform.

9. Contact
For questions regarding these terms please contact Bigiluu support.

By continuing to use the application you accept these terms.
""",
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
        ),
      ),
    );
  }
}