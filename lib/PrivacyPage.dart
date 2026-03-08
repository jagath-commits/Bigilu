import 'package:flutter/material.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Privacy Policy"),
      ),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
"""
Bigiluu values your privacy. This privacy policy explains how your information is used.

1. Information We Collect
We may collect the following information:
- Username
- Profile image
- Posts created by users
- Reading activity
- Saved posts

2. How We Use Information
We use the collected data to:
- Provide and improve the reading platform
- Display user profiles and posts
- Track reader counts
- Enable sharing features

3. Content Visibility
Posts published on Bigiluu may be visible to other users of the platform.

4. Data Security
We take reasonable steps to protect user information and maintain platform security.

5. Third-Party Sharing
Bigiluu does not sell or share personal user data with third parties except when required by law.

6. User Control
Users can control the content they publish and their profile information.

7. Updates
This privacy policy may be updated occasionally to reflect platform improvements.

8. Contact
If you have questions regarding privacy please contact the Bigiluu team.

By using the Bigiluu application you agree to this privacy policy.
""",
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
        ),
      ),
    );
  }
}