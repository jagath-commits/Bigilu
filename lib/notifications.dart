import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  final String userId;
  const NotificationsPage({super.key, required this.userId});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List notifications = [];
  bool isLoading = true;
  String errorMessage = "";

  @override
  void initState() {
    super.initState();
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      // ✅ Hypothesized endpoint for notifications
      final response = await http
          .get(Uri.parse("https://bigiluu.com/api/notifications/getNotifications/${widget.userId}"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          notifications = data['data'] ?? [];
          isLoading = false;
        });
      } else {
        // If 404 or other errors, maybe the endpoint is different or doesn't exist yet.
        // We show a message but handle it gracefully.
        setState(() {
          isLoading = false;
          // errorMessage = "Failed to load notifications. (Status: ${response.statusCode})";
          // If we want to show placeholder/empty for now instead of error:
          notifications = [];
        });
      }
    } catch (e) {
      print("❌ Error fetching notifications: $e");
      setState(() {
        isLoading = false;
        errorMessage = "Unable to connect to service.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);
    const bgColor = Color(0xFFF8F8FA);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        toolbarHeight: 70,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Notifications",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            fontFamily: 'Roboto',
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: brandColor),
            onPressed: fetchNotifications,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: brandColor),
            )
          : errorMessage.isNotEmpty
              ? _buildErrorWidget()
              : notifications.isEmpty
                  ? _buildEmptyWidget()
                  : RefreshIndicator(
                      onRefresh: fetchNotifications,
                      color: brandColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: notifications.length,
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          return _buildNotificationCard(notification);
                        },
                      ),
                    ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            errorMessage,
            style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB11226),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
            ),
            onPressed: fetchNotifications,
            child: const Text("Retry", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(Icons.notifications_none_rounded, size: 80, color: Colors.grey.shade300),
          ),
          const SizedBox(height: 24),
          const Text(
            "No notifications yet",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "When you get updates, they'll appear here.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    // Assuming keys: message, created_at, type, is_read, etc.
    final String title = notification['title'] ?? "New Notification";
    final String message = notification['message'] ?? "";
    final String timeStr = notification['created_at'] ?? "";
    final bool isUnread = notification['is_read'] == 0 || notification['is_read'] == false;

    String formattedTime = "";
    try {
      if (timeStr.isNotEmpty) {
        DateTime dt = DateTime.parse(timeStr);
        formattedTime = DateFormat('MMM d, h:mm a').format(dt);
      }
    } catch (e) {
      formattedTime = timeStr;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB11226).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFFB11226),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isUnread ? FontWeight.w800 : FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        formattedTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isUnread)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFB11226),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
