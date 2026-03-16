import 'package:flutter/material.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          "Privacy Policy",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: brandColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("Data Protection"),
            const SizedBox(height: 12),
            _buildContentText(
                "Bigiluu values your privacy. This privacy policy explains how your information is used."),
            const SizedBox(height: 32),
            
            _buildSectionHeader("1. Information We Collect"),
            _buildBulletPoint("Username"),
            _buildBulletPoint("Profile image"),
            _buildBulletPoint("Posts created by users"),
            _buildBulletPoint("Reading activity"),
            _buildBulletPoint("Saved posts"),
            const SizedBox(height: 24),

            _buildSectionHeader("2. How We Use Information"),
            _buildContentText("We use the collected data to:"),
            _buildBulletPoint("Provide and improve the reading platform"),
            _buildBulletPoint("Display user profiles and posts"),
            _buildBulletPoint("Track reader counts"),
            _buildBulletPoint("Enable sharing features"),
            const SizedBox(height: 24),

            _buildSectionHeader("3. Content Visibility"),
            _buildContentText(
                "Posts published on Bigiluu may be visible to other users of the platform."),
            const SizedBox(height: 24),

            _buildSectionHeader("4. Data Security"),
            _buildContentText(
                "We take reasonable steps to protect user information and maintain platform security."),
            const SizedBox(height: 24),

            _buildSectionHeader("5. Third-Party Sharing"),
            _buildContentText(
                "Bigiluu does not sell or share personal user data with third parties except when required by law."),
            const SizedBox(height: 24),

            _buildSectionHeader("6. User Control"),
            _buildContentText(
                "Users can control the content they publish and their profile information."),
            const SizedBox(height: 24),

            _buildSectionHeader("7. Updates"),
            _buildContentText(
                "This privacy policy may be updated occasionally to reflect platform improvements."),
            const SizedBox(height: 24),

            _buildSectionHeader("8. Contact"),
            _buildContentText(
                "If you have questions regarding privacy please contact the Bigiluu team."),
            const SizedBox(height: 40),
            
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: brandColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: brandColor.withOpacity(0.1)),
              ),
              child: const Text(
                "By using the Bigiluu application you agree to this privacy policy.",
                style: TextStyle(
                  color: brandColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Color(0xFF1A1A1A),
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildContentText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey.shade700,
          height: 1.6,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFB11226),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
