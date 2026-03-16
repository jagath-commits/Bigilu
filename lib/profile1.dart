import 'dart:convert';
import 'dart:io';
import 'package:bigilu/main.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:bigilu/write.dart';
import 'package:bigilu/home.dart';
import 'package:bigilu/hashtag.dart';
import 'package:bigilu/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 🔹 Import the updated EditProfilePage

class ProfilePage extends StatefulWidget {
  final String userId;
  const ProfilePage({super.key, required this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int selectedTab = 0;

  String userName = ""; // Default name
  File? _image;
  String? _networkImageUrl;

  // Sample posts
  List<Map<String, dynamic>> myPosts = [];
  List<Map<String, dynamic>> draftPosts = [];

  List<Map<String, dynamic>> savedPosts = [];

  String fullUrl(String? path) {
    if (path == null || path.isEmpty) {
      return "";
    }

    // ✅ If already a complete URL (http or https), return as-is
    if (path.startsWith("http://") || path.startsWith("https://")) {
      String normalizedPath = path.replaceFirst("http://", "https://");
      // Extract the path part after the domain
      int domainEnd = normalizedPath.indexOf('/', 8); // After https://
      if (domainEnd != -1) {
        String domain = normalizedPath.substring(0, domainEnd);
        String pathPart = normalizedPath.substring(domainEnd);
        // Normalize the path part
        pathPart = pathPart
            .replaceAll("\\", "/")
            .replaceAll(RegExp(r'^/+'), "");
        pathPart = pathPart.replaceAll("Uploads", "uploads");
        pathPart = pathPart.replaceAll("Profile_images", "profile_images");
        pathPart = pathPart.replaceAll("Cover_images", "cover_images");
        pathPart = pathPart.replaceAll("Page_images", "page_images");
        return "$domain/$pathPart";
      }
      return normalizedPath;
    }

    // ✅ Clean up path - normalize slashes and case
    path = path.replaceAll("\\", "/").replaceAll(RegExp(r'^/+'), "");

    // ✅ Normalize folder names to lowercase for consistency
    path = path.replaceAll("Uploads", "uploads");
    path = path.replaceAll("Profile_images", "profile_images");
    path = path.replaceAll("Cover_images", "cover_images");
    path = path.replaceAll("Page_images", "page_images");

    // ✅ If only filename, prepend correct folder
    if (!path.contains("/")) {
      path = "uploads/profile_images/$path";
    }

    // ✅ Return complete HTTPS URL
    return "https://bigiluu.com/$path";
  }

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
    _loadProfileFromBackend();
    _loadUserPosts();
    _loadUserDrafts();
    _loadSavedPosts();
    print("PROFILE USER ID: ${widget.userId}");
  }

  final String baseUrl = "https://bigiluu.com/api/profile/profile/";

  Future<void> _loadUserPosts() async {
    try {
      final response = await http.get(
        Uri.parse("https://bigiluu.com/api/posts/userPosts/${widget.userId}"),
      );

      print("USER POSTS RAW RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          myPosts = List<Map<String, dynamic>>.from(
            (data['data'] ?? []).map(
              (e) => {
                "post_id": e['post_id'].toString(),
                "cover_img": e['cover_img'] ?? "",
                "title": e['title'] ?? "",
                "title_style": e['title_style'],
                "caption": e['caption'] ?? "",
                "hastag": e['hastag'] ?? "",
                "content": e['content'] ?? [],
                "username": e['username'] ?? "",
                "profile_image": e['profile_image'] ?? "",
                "readers_count": e['readers_count'] ?? 0,
              },
            ),
          );
        });

        print("MY POSTS COUNT: ${myPosts.length}");
      }
    } catch (e) {
      print("Error loading posts: $e");
    }
  }

  Future<void> _loadUserDrafts() async {
    try {
      final response = await http.get(
        Uri.parse("https://bigiluu.com/api/posts/userDrafts/${widget.userId}"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          draftPosts = List<Map<String, dynamic>>.from(
            data['drafts'].map((e) {
              final rawContent = jsonDecode(e['draft_content']);

              List<String> previewTexts = [];
              List<String> previewImages = [];

              // 🔥 SAFE PARSING
              if (rawContent is List) {
                for (var page in rawContent) {
                  if (page['blocks'] is List) {
                    for (var block in page['blocks']) {
                      if (block['type'] == 'text' && block['text'] != null) {
                        previewTexts.add(block['text'].toString());
                      }
                      if (block['type'] == 'image' && block['image'] != null) {
                        previewImages.add(block['image'].toString());
                      }
                    }
                  }
                }
              }

              return {
                "post_id": e['draft_id'].toString(),
                "texts": previewTexts,
                "images": previewImages,
                "rawContent": rawContent,
                "cover_img": e['cover_img'], // full json for WritePage
              };
            }),
          );
        });
      }
    } catch (e) {
      print("Error loading drafts: $e");
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Cancel
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              // Clear saved user info
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();

              // Close the dialog
              Navigator.pop(context);

              // Navigate to login page and remove all previous routes
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSavedPosts() async {
    try {
      final response = await http.get(
        Uri.parse("https://bigiluu.com/api/posts/savedPosts/${widget.userId}"),
      );

      print("SAVED POSTS RAW RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          savedPosts = List<Map<String, dynamic>>.from(
            (data['data'] ?? []).map(
              (e) => {
                "post_id": e['post_id'].toString(),
                "cover_img": e['cover_img'] ?? "",
                "title": e['title'] ?? "",
                "title_style": e['title_style'],
                "caption": e['caption'] ?? "",
                "content": e['content'] ?? [],
                "username": e['username'] ?? "",
                "profile_image": e['profile_image'] ?? "",
                "hastag": e['hastag'] ?? "",
              },
            ),
          );
        });

        print("SAVED POSTS COUNT: ${savedPosts.length}");
      }
    } catch (e) {
      print("Error loading saved posts: $e");
    }
  }

  Future<void> _loadProfileFromBackend() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl${widget.userId}"));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          userName = data['username'] ?? "";
          _networkImageUrl = data['profile_image'] != null
              ? fullUrl(data['profile_image'])
              : null;
          _image = null; // Always use backend image if available
        });

        // Optional: save locally for offline caching
        final prefs = await SharedPreferences.getInstance();
        prefs.setString("username", userName);
        if (_networkImageUrl != null) {
          prefs.setString("profile_image_url", _networkImageUrl!);
          prefs.remove("profile_image_path");
        }
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }

  Future<void> _loadLocalProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Username
      userName = prefs.getString("username") ?? "";

      // Image
      String? localPath = prefs.getString("profile_image_path");
      String? imageUrl = prefs.getString("profile_image_url");

      if (localPath != null && File(localPath).existsSync()) {
        _image = File(localPath);
        _networkImageUrl = null;
      } else if (imageUrl != null) {
        _networkImageUrl = imageUrl;
        _image = null;
      } else {
        _image = null;
        _networkImageUrl = null;
      }
    });
  }

  String getDraftPreview(String draftContent) {
    try {
      List<dynamic> pages = jsonDecode(draftContent);
      if (pages.isNotEmpty) {
        for (var block in pages[0]['blocks']) {
          if (block['type'] == 'text' && (block['text'] ?? "").isNotEmpty) {
            return block['text'];
          }
        }
      }
      return "Write your heart...";
    } catch (e) {
      return "Write your heart...";
    }
  }

  Future<void> _deleteDraft(String draftId) async {
    try {
      final response = await http.delete(
        Uri.parse("https://bigiluu.com/api/draft/deleteDraft/$draftId"),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Draft Deleted Successfully")),
        );

        _loadUserDrafts(); // 🔥 refresh drafts
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Failed to delete draft")));
      }
    } catch (e) {
      print("Delete draft error: $e");
    }
  }

  void _confirmDeleteDraft(String draftId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Draft"),
        content: const Text("Are you sure you want to delete this draft?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteDraft(draftId);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }





  Widget _buildGridSection() {
    final list = _getSelectedList();
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 64,
              color: Colors.grey.shade200,
            ),
            const SizedBox(height: 16),
            Text(
              "No posts found",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: list.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 24,
        childAspectRatio: 0.65,
      ),
      itemBuilder: (context, index) {
        final post = list[index];
        final String postId = post['post_id'].toString();
        final String img = post['cover_img'] ?? "";
        final String title = (post['title'] ?? "").toString();

        return GestureDetector(
          onTap: () async {
            if (selectedTab == 1) {
              // Drafts
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WritePage(
                    draftId: postId,
                    draftContent: jsonEncode(post['rawContent']),
                    draftCover: post['cover_img'],
                  ),
                ),
              );
              _loadUserDrafts();
              return;
            }

            // Normal Posts & Saved
            List<Map<String, dynamic>> sourceList = selectedTab == 0
                ? myPosts
                : savedPosts;
            int clickedIndex = sourceList.indexWhere(
              (p) => p['post_id'] == postId,
            );

            // Loading Overlay
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const Center(
                child: CircularProgressIndicator(color: Color(0xFFB11226)),
              ),
            );

            List<Map<String, dynamic>> fullPosts = [];
            try {
              for (var p in sourceList) {
                final response = await http.get(
                  Uri.parse(
                    "https://bigiluu.com/api/posts/singlePost/${p['post_id']}",
                  ),
                );
                if (response.statusCode == 200) {
                  fullPosts.add(jsonDecode(response.body));
                }
              }
            } finally {
              Navigator.pop(context); // Close loading
            }

            final removedPostId = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileFeedViewer(
                  posts: fullPosts,
                  initialIndex: clickedIndex < 0 ? 0 : clickedIndex,
                  title: selectedTab == 0 ? "My Books" : "Saved",
                  userId: widget.userId,
                ),
              ),
            );

            if (removedPostId != null) {
              _loadUserPosts();
              _loadSavedPosts();
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(4, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 3D Page Edges
                Positioned(
                  right: 0,
                  top: 4,
                  bottom: 4,
                  width: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(6),
                      ),
                      border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    ),
                  ),
                ),

                // Cover
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (img.isNotEmpty)
                          Image.network(
                            img,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(color: Colors.grey.shade100);
                            },
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.book_rounded,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        else
                          Container(
                            color: Colors.grey.shade200,
                            child: Center(
                              child: Text(
                                title.isNotEmpty ? title : "No Cover",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),

                        // Depth Overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black.withOpacity(0.4),
                                Colors.black.withOpacity(0.05),
                                Colors.transparent,
                                Colors.black.withOpacity(0.2),
                              ],
                              stops: const [0.0, 0.05, 0.2, 1.0],
                            ),
                          ),
                        ),

                        // Title Overlay
                        Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (post['hastag'] != null &&
                                  post['hastag'].toString().isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "#${post['hastag']}",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  fontFamily: 'serif',
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Delete button for drafts
                if (selectedTab == 1)
                  Positioned(
                    top: 6,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => _confirmDeleteDraft(postId),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Container(
        color: const Color(0xFFF8F9FA),
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // Profile Header Section
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(32),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildAvatar(),
                          const SizedBox(height: 16),
                          Text(
                            userName.isNotEmpty ? userName : "User",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Creative Storyteller",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Stats Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildStatItem("${myPosts.length}", "Books"),
                              _buildStatVerticalDivider(),
                              _buildStatItem("${savedPosts.length}", "Saved"),
                              _buildStatVerticalDivider(),
                              _buildStatItem("${draftPosts.length}", "Drafts"),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EditProfilePage(
                                          userId: widget.userId,
                                        ),
                                      ),
                                    );
                                    if (result != null && result is Map) {
                                      setState(() {
                                        userName =
                                            result['username'] ?? userName;
                                        _networkImageUrl =
                                            result['profile_image'] ??
                                            _networkImageUrl;
                                        _image = null;
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.edit_note_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    "Edit Profile",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFB11226),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: IconButton(
                                  onPressed: _confirmLogout,
                                  icon: const Icon(
                                    Icons.logout_rounded,
                                    color: Color(0xFFE53935),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // Sticky Tabs Section
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  minHeight: 70,
                  maxHeight: 70,
                  child: Container(
                    color: const Color(0xFFF8F9FA),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          _buildModernTab("Books", 0),
                          _buildModernTab("Drafts", 1),
                          _buildModernTab("Saved", 2),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ];
          },
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildGridSection(),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A1A),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatVerticalDivider() {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.grey.shade200,
    );
  }

  Widget _buildModernTab(String title, int index) {
    final bool isSelected = selectedTab == index;
    const brandColor = Color(0xFFB11226);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? brandColor : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: brandColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isSelected ? Colors.white : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }

  // ============================
  // Avatar
  // ============================
  Widget _buildAvatar() {
    ImageProvider provider;

    if (_image != null) {
      provider = FileImage(_image!);
    } else if (_networkImageUrl != null && _networkImageUrl!.isNotEmpty) {
      provider = NetworkImage(_networkImageUrl!);
    } else {
      provider = const NetworkImage('https://i.stack.imgur.com/l60Hf.png');
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFB11226).withOpacity(0.5),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB11226).withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: MediaQuery.of(context).size.width < 360
            ? 40
            : 48, // Reduced from 45/55
        backgroundImage: provider,
      ),
    );
  }

  // ============================
  // Tabs
  // ============================
  List<Map<String, dynamic>> _getSelectedList() {
    if (selectedTab == 0) return myPosts;
    if (selectedTab == 1) return draftPosts;
    return savedPosts;
  }

  // ============================
  // Bottom Navigation
  // ============================
  Widget _buildBottomNavigationBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _build3DNavItem(context, Icons.home_rounded, "Home", () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage()),
                  (route) => false,
                );
              }, isActive: false),
              _build3DNavItem(context, Icons.explore_rounded, "Explore", () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HashtagPage()),
                );
              }, isActive: false),
              _build3DNavItem(context, Icons.edit_rounded, "Write", () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WritePage()),
                );
                if (result == true) {
                  await _loadUserDrafts();
                  setState(() => selectedTab = 1);
                }
              }, isActive: false),
              _build3DNavItem(
                context,
                Icons.person_rounded,
                "Profile",
                () {},
                isActive: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _build3DNavItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool isActive = false,
  }) {
    double screenWidth = MediaQuery.of(context).size.width;
    double iconInternalSize = screenWidth < 360 ? 24 : 28;
    double fontSize = screenWidth < 360 ? 11 : 12;

    Color activeColor = const Color(0xFFB11226);
    Color inactiveColor = Colors.grey.shade400;

    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? activeColor : inactiveColor,
            size: iconInternalSize,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? activeColor : inactiveColor,
              fontSize: fontSize,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              fontFamily: 'Roboto',
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class FullPostPage extends StatefulWidget {
  final String postId;
  final bool showDelete; // ✅ ADD THIS
  //final bool openFirstContent; // ✅ ADD THIS

  const FullPostPage({
    super.key,
    required this.postId,
    this.showDelete = false, // ✅ DEFAULT FALSE
    //this.openFirstContent = false, // ✅ DEFAULT FALSE
  });

  @override
  State<FullPostPage> createState() => _FullPostPageState();
}

class _FullPostPageState extends State<FullPostPage> {
  List<dynamic> pages = [];
  String? coverImg;
  String? caption;
  int readersCount = 0; // track reader count for display
  bool loading = true;

  int currentPage = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();

    _pageController = PageController();

    _loadPost();
  }

  Future<void> _loadPost() async {
    try {
      // switch to getPost to retrieve readers_count and owner info
      final response = await http.get(
        Uri.parse("https://bigiluu.com/api/posts/getPost/${widget.postId}"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          coverImg = data['cover_img'];
          caption = data['caption'];
          pages = data['content'];
          readersCount = data['readers_count'] ?? 0;
          loading = false;
        });
      } else {
        loading = false;
      }
    } catch (e) {
      print("Error loading post: $e");
      loading = false;
    }
  }

  Future<void> _deletePost() async {
    try {
      final response = await http.delete(
        Uri.parse("https://bigiluu.com/api/posts/deletePost/${widget.postId}"),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Post Deleted Successfully")),
        );

        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Failed to delete post")));
      }
    } catch (e) {
      print("Delete error: $e");
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Post"),
        content: const Text("Are you sure you want to delete this post?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePost();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = pages.length + 1; // include cover page as first page

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              "Reading",
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                fontFamily: 'serif',
              ),
            ),
            Text(
              "Page ${currentPage + 1} of $totalPages",
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        actions: widget.showDelete
            ? [
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                  ),
                  onPressed: _confirmDelete,
                ),
              ]
            : [const SizedBox(width: 48)],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                fit: StackFit.expand,
                children: [
                  // PAGE VIEW
                  Positioned.fill(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: totalPages,
                      onPageChanged: (index) {
                        setState(() {
                          currentPage = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        // Custom premium container for each page
                        return SizedBox.expand(
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(16, 8, 16, 75),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFDFBF7,
                              ), // Premium cream paper
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Spine Binding Effect
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: 30,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Colors.black.withOpacity(0.15),
                                            Colors.black.withOpacity(0.05),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Paper Texture Overlay
                                  Positioned.fill(
                                    child: Opacity(
                                      opacity: 0.02,
                                      child: Image.network(
                                        "https://www.transparenttextures.com/patterns/paper-fibers.png",
                                        repeat: ImageRepeat.repeat,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox(),
                                      ),
                                    ),
                                  ),

                                  // Content
                                  if (index == 0)
                                    // COVER PAGE
                                    SingleChildScrollView(
                                      padding: const EdgeInsets.fromLTRB(
                                        45,
                                        40,
                                        32,
                                        40,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (coverImg != null)
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.network(
                                                coverImg!,
                                                fit: BoxFit.contain,
                                                loadingBuilder:
                                                    (context, child, progress) {
                                                      if (progress == null)
                                                        return child;
                                                      return Container(
                                                        height: 200,
                                                        color: Colors
                                                            .grey
                                                            .shade100,
                                                        child: const Center(
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        ),
                                                      );
                                                    },
                                              ),
                                            ),
                                          if (caption != null &&
                                              caption!.isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    0,
                                                    24,
                                                    0,
                                                    12,
                                                  ),
                                              child: Text(
                                                caption!,
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w800,
                                                  fontFamily: 'serif',
                                                  height: 1.3,
                                                  color: Color(0xFF2C2C2C),
                                                ),
                                              ),
                                            ),
                                          if (readersCount > 0)
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.visibility,
                                                  size: 16,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  "$readersCount readers",
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    )
                                  else
                                    // CONTENT PAGES
                                    Builder(
                                      builder: (context) {
                                        final page = pages[index - 1];
                                        return SingleChildScrollView(
                                          padding: const EdgeInsets.fromLTRB(
                                            50,
                                            45,
                                            35,
                                            60,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ...(page['blocks'] as List? ?? []).map<
                                                Widget
                                              >((block) {
                                                if (block['type'] == "text") {
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 16,
                                                        ),
                                                    child: Text(
                                                      block['text'] ?? "",
                                                      style: TextStyle(
                                                        fontSize:
                                                            (page['fontSize'] ??
                                                                    18)
                                                                .toDouble(),
                                                        color: _parseColor(
                                                          page['fontColor'],
                                                        ).withOpacity(0.85),
                                                        fontFamily:
                                                            page['fontFamily'] ??
                                                            'Roboto',
                                                        height: 1.6,
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                                  );
                                                }

                                                if (block['type'] == "image" &&
                                                    block['image'] != null &&
                                                    block['image']
                                                        .toString()
                                                        .isNotEmpty) {
                                                  return Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          bottom: 20,
                                                          top: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withOpacity(0.1),
                                                          blurRadius: 8,
                                                          offset: const Offset(
                                                            0,
                                                            4,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      child: Image.network(
                                                        block['image'],
                                                        fit: BoxFit.cover,
                                                        loadingBuilder:
                                                            (
                                                              context,
                                                              child,
                                                              progress,
                                                            ) {
                                                              if (progress ==
                                                                  null)
                                                                return child;
                                                              return Container(
                                                                height: 200,
                                                                color: Colors
                                                                    .grey
                                                                    .shade100,
                                                                child: const Center(
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                        errorBuilder:
                                                            (
                                                              _,
                                                              __,
                                                              ___,
                                                            ) => Container(
                                                              height: 100,
                                                              color: Colors
                                                                  .grey
                                                                  .shade100,
                                                              child: const Icon(
                                                                Icons
                                                                    .broken_image,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                            ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                                return const SizedBox();
                                              }),
                                            ],
                                          ),
                                        );
                                      },
                                    ),

                                  // Page number indicator
                                  Positioned(
                                    bottom: 24,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: Text(
                                        "— ${index + 1} —",
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          letterSpacing: 1.2,
                                          fontFamily: 'serif',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Color _parseColor(dynamic colorValue) {
    try {
      if (colorValue == null) return Colors.black;
      return Color(int.parse(colorValue.toString()));
    } catch (_) {
      return Colors.black;
    }
  }
}

class ProfileFeedViewer extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final int initialIndex;
  final String title;
  final String userId;

  const ProfileFeedViewer({
    super.key,
    required this.posts,
    required this.initialIndex,
    required this.title,
    required this.userId,
  });

  @override
  State<ProfileFeedViewer> createState() => _ProfileFeedViewerState();
}

class _ProfileFeedViewerState extends State<ProfileFeedViewer> {
  late List<Map<String, dynamic>> posts;
  late PageController controller;

  String _fullUrl(String? path) {
    if (path == null || path.isEmpty) return "";
    if (path.startsWith("http://") || path.startsWith("https://")) {
      return path.replaceFirst("http://", "https://");
    }
    path = path.replaceAll("\\", "/").replaceAll(RegExp(r'^/+'), "");
    path = path.replaceAll("Uploads", "uploads");
    path = path.replaceAll("Profile_images", "profile_images");
    path = path.replaceAll("Cover_images", "cover_images");
    path = path.replaceAll("Page_images", "page_images");
    if (!path.contains("/")) path = "uploads/cover_images/$path";
    return "https://bigiluu.com/$path";
  }

  @override
  void initState() {
    super.initState();
    posts = List.from(widget.posts);
    controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: const Color.fromARGB(255, 248, 247, 247),
        elevation: 1,
      ),
      body: posts.isEmpty
          ? const Center(
              child: Text("No Saved Posts", style: TextStyle(fontSize: 16)),
            )
          : PageView.builder(
              controller: controller,
              scrollDirection: Axis.vertical,
              itemCount: posts.isEmpty ? 1 : posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final String img = _fullUrl(post['cover_img'] ?? '');
                final String caption = (post['caption'] ?? '').toString();
                final String hashtag = (post['hastag'] ?? '').toString();
                final String username = (post['username'] ?? 'Storyteller')
                    .toString();
                final String profileImg = _fullUrl(post['profile_image'] ?? '');
                final int readersCount = post['readers_count'] ?? 0;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ─── HEADER ───────────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Colors.grey.shade200,
                                    backgroundImage: profileImg.isNotEmpty
                                        ? NetworkImage(profileImg)
                                        : null,
                                    child: profileImg.isEmpty
                                        ? const Icon(
                                            Icons.person,
                                            color: Colors.grey,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          username,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                        ),
                                        const Text(
                                          "Storyteller",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Delete button
                                  if (widget.title == "My Stories" ||
                                      widget.title == "Post" ||
                                      widget.title == "My Books")
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.redAccent,
                                        size: 22,
                                      ),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text("Delete Post"),
                                            content: const Text(
                                              "Are you sure you want to delete this post?",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: const Text("Cancel"),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: const Text(
                                                  "Delete",
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          try {
                                            final response = await http.delete(
                                              Uri.parse(
                                                "https://bigiluu.com/api/posts/deletePost/${post['post_id']}",
                                              ),
                                            );
                                            if (response.statusCode == 200) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    "Post deleted successfully",
                                                  ),
                                                ),
                                              );
                                              setState(() {
                                                posts.removeAt(index);
                                              });
                                              if (posts.isEmpty) {
                                                Navigator.pop(
                                                  context,
                                                  post['post_id'].toString(),
                                                );
                                              }
                                            }
                                          } catch (e) {
                                            print("Delete error: $e");
                                          }
                                        }
                                      },
                                    ),
                                  // Readers count chip
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFB11226,
                                      ).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.auto_stories_rounded,
                                          color: Color(0xFFB11226),
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "$readersCount",
                                          style: const TextStyle(
                                            color: Color(0xFFB11226),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ─── BOOK COVER ───────────────────────────────────
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullScreenPostViewer(
                                        pages: post['content'] ?? [],
                                        username: post['username'] ?? "",
                                        profileImage:
                                            post['profile_image'] ?? "",
                                        postId: post['post_id'],
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Hero(
                                    tag: "feed_post_${post['post_id']}",
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(12),
                                          bottomRight: Radius.circular(12),
                                          topLeft: Radius.circular(6),
                                          bottomLeft: Radius.circular(6),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.35,
                                            ),
                                            blurRadius: 20,
                                            offset: const Offset(10, 14),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        children: [
                                          // Page edges
                                          Positioned(
                                            right: 0,
                                            top: 6,
                                            bottom: 6,
                                            width: 14,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    const BorderRadius.horizontal(
                                                      right: Radius.circular(8),
                                                    ),
                                                border: Border.all(
                                                  color: Colors.grey
                                                      .withOpacity(0.2),
                                                ),
                                              ),
                                            ),
                                          ),
                                          // Front cover
                                          Positioned.fill(
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                right: 12,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    if (img.isNotEmpty)
                                                      Image.network(
                                                        img,
                                                        fit: BoxFit.cover,
                                                        loadingBuilder:
                                                            (
                                                              ctx,
                                                              child,
                                                              progress,
                                                            ) {
                                                              if (progress ==
                                                                  null)
                                                                return child;
                                                              return Container(
                                                                color: Colors
                                                                    .grey
                                                                    .shade100,
                                                              );
                                                            },
                                                        errorBuilder:
                                                            (
                                                              _,
                                                              __,
                                                              ___,
                                                            ) => Container(
                                                              color: Colors
                                                                  .grey
                                                                  .shade200,
                                                              child: const Icon(
                                                                Icons
                                                                    .book_rounded,
                                                                color:
                                                                    Colors.grey,
                                                                size: 40,
                                                              ),
                                                            ),
                                                      )
                                                    else
                                                      Container(
                                                        color: Colors
                                                            .grey
                                                            .shade200,
                                                        child: const Icon(
                                                          Icons.book_rounded,
                                                          color: Colors.grey,
                                                          size: 40,
                                                        ),
                                                      ),
                                                    // Depth overlay
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment
                                                              .centerLeft,
                                                          end: Alignment
                                                              .centerRight,
                                                          colors: [
                                                            Colors.black
                                                                .withOpacity(
                                                                  0.5,
                                                                ),
                                                            Colors.black
                                                                .withOpacity(
                                                                  0.1,
                                                                ),
                                                            Colors.transparent,
                                                            Colors.black
                                                                .withOpacity(
                                                                  0.3,
                                                                ),
                                                          ],
                                                          stops: const [
                                                            0.0,
                                                            0.05,
                                                            0.25,
                                                            1.0,
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    // Title overlay
                                                    Positioned(
                                                      bottom: 32,
                                                      left: 20,
                                                      right: 16,
                                                      child: Text(
                                                        caption,
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          fontFamily: 'serif',
                                                          height: 1.2,
                                                          shadows: [
                                                            Shadow(
                                                              color: Colors
                                                                  .black87,
                                                              blurRadius: 16,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // ─── METADATA ─────────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (caption.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        caption,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF4A4A4A),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      if (hashtag.isNotEmpty)
                                        Expanded(
                                          child: Text(
                                            hashtag,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFFB11226),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // ─── ACTION BUTTONS ────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                FullScreenPostViewer(
                                                  pages: post['content'] ?? [],
                                                  username:
                                                      post['username'] ?? "",
                                                  profileImage:
                                                      post['profile_image'] ??
                                                      "",
                                                  postId: post['post_id'],
                                                ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.menu_book_rounded,
                                        size: 16,
                                      ),
                                      label: const Text("Read"),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFB11226,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFB11226),
                                          width: 1.2,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (widget.title == "Saved")
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          try {
                                            final response = await http.delete(
                                              Uri.parse(
                                                "https://bigiluu.com/api/posts/removeSavedPost/${widget.userId}/${post['post_id']}",
                                              ),
                                            );
                                            if (response.statusCode == 200) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    "Removed from saved",
                                                  ),
                                                ),
                                              );
                                              setState(() {
                                                posts.removeAt(index);
                                              });
                                              if (posts.isEmpty) {
                                                Navigator.pop(
                                                  context,
                                                  post['post_id'].toString(),
                                                );
                                              }
                                            }
                                          } catch (e) {
                                            print("Remove saved error: $e");
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.bookmark_remove_outlined,
                                          size: 16,
                                        ),
                                        label: const Text("Unsave"),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.grey.shade600,
                                          side: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1.2,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            const Divider(thickness: 0.4, height: 1),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });
  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}
