import 'package:flutter/material.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          "Terms & Conditions",
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
            _buildSectionHeader("Welcome to Bigiluu"),
            const SizedBox(height: 12),
            _buildContentText(
                "By using the Bigiluu application you agree to the following terms and conditions."),
            const SizedBox(height: 32),

            _buildSectionHeader("1. Platform Usage"),
            _buildContentText(
                "Bigiluu is a digital platform that allows users to publish, read, and share short books or posts. Users can create content and publish it for other readers."),
            const SizedBox(height: 24),

            _buildSectionHeader("2. User Content"),
            _buildContentText(
                "Users are responsible for the content they publish. Content must not contain illegal, abusive, or copyrighted material without permission."),
            const SizedBox(height: 24),

            _buildSectionHeader("3. Account Responsibility"),
            _buildContentText(
                "Users are responsible for maintaining the security of their account and any activity that occurs under their account."),
            const SizedBox(height: 24),

            _buildSectionHeader("4. Content Removal"),
            _buildContentText(
                "Bigiluu reserves the right to remove any content that violates community guidelines or applicable laws."),
            const SizedBox(height: 24),

            _buildSectionHeader("5. Intellectual Property"),
            _buildContentText(
                "Users retain ownership of the content they publish but grant Bigiluu permission to display and distribute the content within the platform."),
            const SizedBox(height: 24),

            _buildSectionHeader("6. Sharing"),
            _buildContentText(
                "Users may share posts through the share feature, but the content must not be altered or misrepresented."),
            const SizedBox(height: 24),

            _buildSectionHeader("7. Service Changes"),
            _buildContentText(
                "Bigiluu may update or modify the platform features at any time to improve user experience."),
            const SizedBox(height: 24),

            _buildSectionHeader("8. Limitation of Liability"),
            _buildContentText(
                "Bigiluu is not responsible for any damages resulting from the use of the platform."),
            const SizedBox(height: 24),

            _buildSectionHeader("9. Contact"),
            _buildContentText(
                "For questions regarding these terms please contact Bigiluu support."),
            const SizedBox(height: 40),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: brandColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: brandColor.withOpacity(0.1)),
              ),
              child: const Text(
                "By continuing to use the application you accept these terms.",
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
}
