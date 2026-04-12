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
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

List<dynamic> extractPages(dynamic rawContent) {
  if (rawContent == null) return [];
  if (rawContent is List) return rawContent;
  if (rawContent is String) {
    try {
      final decoded = jsonDecode(rawContent);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded.containsKey('pages')) {
        return decoded['pages'] ?? [];
      }
    } catch (e) {
      print("Error decoding content: $e");
    }
  }
  return [];
}

// 🔹 Import the updated EditProfilePage

class ProfilePage extends StatefulWidget {
  final String userId;
  final bool isPublicView; // 👈 ADD THIS
  final String? initialPostId;

  const ProfilePage({
    super.key,
    required this.userId,
    this.isPublicView = false,
    this.initialPostId, // ✅ ONLY THIS
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int selectedTab = 0; // 0=Books, 1=Drafts, 2=Saved
  bool _isOpeningGridPost = false; // ✅ Guard against double-tap

  String userName = ""; // Default name
  File? _image;
  String? _networkImageUrl;

  // Sample posts
  List<Map<String, dynamic>> myPosts = [];
  List<Map<String, dynamic>> draftPosts = [];

  List<Map<String, dynamic>> savedPosts = [];

  String fullUrl(String? path) {
    if (path == null || path.isEmpty) return "";

    path = path.trim();

    // 🚨 FIX: remove double domain
    if (path.contains("https://bigiluu.com/https://")) {
      path = path.replaceFirst("https://bigiluu.com/", "");
    }

    if (path.startsWith("http")) {
      return path;
    }

    path = path.replaceAll("\\", "/").replaceAll(RegExp(r'^/+'), "");

    if (!path.contains("/")) {
      path = "uploads/profile_images/$path";
    }

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.initialPostId != null) {
        await Future.delayed(const Duration(milliseconds: 800));
        _openSpecificPost(widget.initialPostId!);
      }
    });
  }

  void _openSpecificPost(String postId) async {
    print("🔥 OPEN PROFILE POST: $postId");

    try {
      final response = await http.get(
        Uri.parse("https://bigiluu.com/api/posts/singlePost/$postId"),
      );

      if (response.statusCode == 200) {
        final postData = jsonDecode(response.body);

        // ✅ FIX HERE
        postData['profile_image'] = fullUrl(postData['profile_image']);
        postData['cover_img'] = fullUrl(postData['cover_img']);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileFeedViewer(
              posts: [postData],
              initialIndex: 0,
              title: "Post",
              userId: widget.userId,
              isPublicView: widget.isPublicView,
            ),
          ),
        );
      }
    } catch (e) {
      print("❌ Error opening profile post: $e");
    }
  }

  final String baseUrl = "https://bigiluu.com/api/profile/profile/";

  Future<void> _loadUserPosts() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              "https://bigiluu.com/api/posts/userPosts/${widget.userId}",
            ),
          )
          .timeout(const Duration(seconds: 25));

      print("USER POSTS RAW RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (!mounted) return;
        setState(() {
          myPosts = List<Map<String, dynamic>>.from(
            (data['data'] ?? []).map(
              (e) => {
                "post_id": e['post_id'].toString(),
                "cover_img": e['cover_img'] ?? "",
                "title": e['title'] ?? "",
                "title_style": e['title_style'],
                "titleFontSize": e['titleFontSize'],
                "titleColor": e['titleColor'],
                "titleFontFamily": e['titleFontFamily'],
                "caption": e['caption'] ?? "",
                "hastag": e['hastag'] ?? "",
                "content": e['content'] ?? [],
                "summary": e['summary'] ?? "",
                "username": e['username'] ?? "",
                "profile_image": fullUrl(e['profile_image']),
                "readers_count": e['readers_count'] ?? 0,
                "support_count": e['support_count'] ?? 0,
                "acknowledgment": e['acknowledgment'] ?? "",
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
      final response = await http
          .get(
            Uri.parse(
              "https://bigiluu.com/api/posts/userDrafts/${widget.userId}",
            ),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (!mounted) return;
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
                        previewImages.add(
                          fullUrl("uploads/page_images/${block['image']}"),
                        );
                      }
                    }
                  }
                }
              }

              return {
                "post_id": e['draft_id'].toString(),
                "title": e['title'] ?? "",
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
      final response = await http
          .get(
            Uri.parse(
              "https://bigiluu.com/api/posts/savedPosts/${widget.userId}",
            ),
          )
          .timeout(const Duration(seconds: 25));

      print("SAVED POSTS RAW RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (!mounted) return;
        setState(() {
          savedPosts = List<Map<String, dynamic>>.from(
            (data['data'] ?? []).map(
              (e) => {
                "post_id": e['post_id'].toString(),
                "cover_img": e['cover_img'] ?? "",
                "title": e['title'] ?? "",
                "title_style": e['title_style'],
                "titleFontSize": e['titleFontSize'],
                "titleColor": e['titleColor'],
                "titleFontFamily": e['titleFontFamily'],
                "caption": e['caption'] ?? "",
                "content": e['content'] ?? [],
                "username": e['username'] ?? "",
                "profile_image": fullUrl(e['profile_image']),
                "hastag": e['hastag'] ?? "",
                "readers_count": e['readers_count'] ?? 0,
                "support_count": e['support_count'] ?? 0,
                "acknowledgment": e['acknowledgment'] ?? "",
                "summary": e['summary'] ?? "",
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
      final response = await http
          .get(Uri.parse("$baseUrl${widget.userId}"))
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (!mounted) return;
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
    if (!mounted) return;
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

  List<dynamic> _convertDraftImages(List<dynamic> content) {
    return content.map((page) {
      if (page['blocks'] is List) {
        page['blocks'] = page['blocks'].map((block) {
          if (block['type'] == 'image' &&
              block['image'] != null &&
              block['image'].toString().isNotEmpty) {
            String img = block['image'];

            // ✅ Already full URL
            if (img.startsWith("http")) {
              return block;
            }

            // ✅ Already has uploads path
            if (img.contains("uploads/")) {
              block['image'] = fullUrl(img);
            }
            // ✅ Only filename
            else {
              block['image'] = fullUrl("uploads/page_images/$img");
            }
          }
          return block;
        }).toList();
      }
      return page;
    }).toList();
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
            if (_isOpeningGridPost) return;
            setState(() => _isOpeningGridPost = true);

            try {
              if (!widget.isPublicView && selectedTab == 1) {
                // Drafts
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WritePage(
                      draftId: postId,
                      draftContent: jsonEncode(
                        _convertDraftImages(post['rawContent']),
                      ),
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

              final removedPostId = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileFeedViewer(
                    posts: sourceList,
                    initialIndex: clickedIndex < 0 ? 0 : clickedIndex,
                    title: selectedTab == 0 ? "My Books" : "Saved",
                    userId: widget.userId,
                    isPublicView: widget.isPublicView,
                  ),
                ),
              );

              if (removedPostId != null) {
                _loadUserPosts();
                _loadSavedPosts();
              }
            } finally {
              if (mounted) {
                setState(() => _isOpeningGridPost = false);
              }
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
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.book_rounded,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        else
                          _buildDraftPreview(post, title),

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
                if (!widget.isPublicView && selectedTab == 1)
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

  Widget _buildDraftPreview(Map<String, dynamic> post, String title) {
    String firstImg = "";
    if (post['images'] != null && (post['images'] as List).isNotEmpty) {
      firstImg = post['images'][0];
    }

    if (firstImg.isNotEmpty) {
      return Image.network(
        firstImg,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildDraftTextPreview(post, title),
      );
    }

    return _buildDraftTextPreview(post, title);
  }

  Widget _buildDraftTextPreview(Map<String, dynamic> post, String title) {
    String firstText = "";
    if (post['texts'] != null && (post['texts'] as List).isNotEmpty) {
      firstText = post['texts'][0];
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (firstText.isNotEmpty)
            Text(
              firstText,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: Colors.black.withOpacity(0.6),
                fontFamily: 'serif',
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            )
          else
            Icon(
              Icons.edit_note_rounded,
              color: Colors.grey.shade300,
              size: 40,
            ),
        ],
      ),
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
                            children: widget.isPublicView
                                ? [_buildStatItem("${myPosts.length}", "Books")]
                                : [
                                    _buildStatItem(
                                      "${myPosts.length}",
                                      "Books",
                                    ),
                                    _buildStatVerticalDivider(),
                                    _buildStatItem(
                                      "${savedPosts.length}",
                                      "Saved",
                                    ),
                                    _buildStatVerticalDivider(),
                                    _buildStatItem(
                                      "${draftPosts.length}",
                                      "Drafts",
                                    ),
                                  ],
                          ),

                          const SizedBox(height: 32),

                          // Action Buttons
                          if (!widget.isPublicView)
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
                        children: widget.isPublicView
                            ? [
                                _buildModernTab("Books", 0), // 👈 only this
                              ]
                            : [
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
      bottomNavigationBar: widget.isPublicView
          ? null
          : _buildBottomNavigationBar(context),
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
    if (widget.isPublicView) return myPosts; // 👈 FIX

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

        if (!mounted) return;
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
                                        errorBuilder: (_, _, _) =>
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
                                            ExpandablePostImage(
                                              imageUrl: coverImg!,
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
                                                  return ExpandablePostImage(
                                                    imageUrl: block['image'],
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
  final bool isPublicView;

  const ProfileFeedViewer({
    super.key,
    required this.posts,
    required this.initialIndex,
    required this.title,
    required this.userId,
    required this.isPublicView,
  });

  @override
  State<ProfileFeedViewer> createState() => _ProfileFeedViewerState();
}

class _ProfileFeedViewerState extends State<ProfileFeedViewer> {
  late List<Map<String, dynamic>> posts;
  late PageController controller;
  Set<String> likedPosts = {};
  Set<String> savedPosts = {};
  bool _isOpeningPost = false;
  int currentPage = 0;
  late List<GlobalKey> _cardKeys;

  Future<void> _sharePostAsImage(String postId, int index) async {
    try {
      final boundary =
          _cardKeys[index].currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        // ignore: deprecated_member_use
        await Share.share(
          "Check out this story on Bigiluu! https://bigiluu.com/post/$postId",
        );
        return;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final tempDir = Directory.systemTemp;
      final file = File(
        '${tempDir.path}/bigilu_post_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'Check out this story on Bigiluu! https://bigiluu.com/post/$postId',
      );
    } catch (e) {
      debugPrint("Error sharing post image: $e");
      // ignore: deprecated_member_use
      await Share.share(
        "Check out this story on Bigiluu! https://bigiluu.com/post/$postId",
      );
    }
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<void> _loadInteractionsLocal() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      likedPosts = (prefs.getStringList('cached_liked_posts') ?? []).toSet();
      savedPosts = (prefs.getStringList('cached_saved_posts') ?? []).toSet();
    });
  }

  Future<void> _saveInteractionsLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('cached_liked_posts', likedPosts.toList());
    await prefs.setStringList('cached_saved_posts', savedPosts.toList());
  }

  Future<void> fetchUserInteractions() async {
    String? userId = await getUserId();
    if (userId == null) return;

    // 1. Fetch Saved Posts
    try {
      final savedResponse = await http
          .get(Uri.parse("https://bigiluu.com/api/posts/savedPosts/$userId"))
          .timeout(const Duration(seconds: 10));

      if (savedResponse.statusCode == 200) {
        final data = jsonDecode(savedResponse.body);
        final List savedData = data['data'] ?? [];
        if (mounted) {
          setState(() {
            savedPosts = savedData.map((e) => e['post_id'].toString()).toSet();
          });
        }
      }
    } catch (e) {
      print("Error fetching saved: $e");
    }

    // 2. Fetch Supported Posts
    try {
      final likedResponse = await http
          .get(
            Uri.parse("https://bigiluu.com/api/posts/supportedPosts/$userId"),
          )
          .timeout(const Duration(seconds: 10));

      if (likedResponse.statusCode == 200) {
        final data = jsonDecode(likedResponse.body);
        final List likedData = data['data'] ?? [];
        if (mounted) {
          setState(() {
            likedPosts = likedData.map((e) => e['post_id'].toString()).toSet();
          });
          _saveInteractionsLocal();
        }
      }
    } catch (e) {
      print("Error fetching supported: $e");
    }
  }

  Future<void> toggleLike(String postId) async {
    final isAlreadyLiked = likedPosts.contains(postId);
    final String? userId = await getUserId();
    if (userId == null) return;

    setState(() {
      if (isAlreadyLiked) {
        likedPosts.remove(postId);
      } else {
        likedPosts.add(postId);
      }

      for (var p in posts) {
        if (p['post_id']?.toString() == postId) {
          int current =
              int.tryParse(p['support_count']?.toString() ?? "0") ?? 0;
          p['support_count'] = isAlreadyLiked
              ? (current - 1).clamp(0, 999999)
              : (current + 1);
          break;
        }
      }
    });

    _saveInteractionsLocal();

    try {
      await http.post(
        Uri.parse("https://bigiluu.com/api/posts/toggleSupport"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "post_id": postId,
          "user_id": userId,
          "action": isAlreadyLiked ? "unlike" : "like",
        }),
      );
    } catch (e) {
      print("Support API error: $e");
    }
  }

  Future<void> toggleSave(String postId) async {
    String? userId = await getUserId();
    if (userId == null) return;

    final bool isAlreadySaved = savedPosts.contains(postId);

    try {
      if (isAlreadySaved) {
        final response = await http
            .delete(
              Uri.parse(
                "https://bigiluu.com/api/posts/removeSavedPost/$userId/$postId",
              ),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          setState(() {
            savedPosts.remove(postId);
          });
          _saveInteractionsLocal();
        }
      } else {
        final response = await http
            .post(
              Uri.parse("https://bigiluu.com/api/posts/savePost"),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'user_id': userId, 'post_id': postId}),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          setState(() {
            savedPosts.add(postId);
          });
          _saveInteractionsLocal();
        }
      }
    } catch (e) {
      print("Error toggling save: $e");
    }
  }

  String fullUrl(String? path) {
    if (path == null || path.isEmpty) return "";

    path = path.trim();

    // 🚨 FIX: remove double domain
    if (path.contains("https://bigiluu.com/https://")) {
      path = path.replaceFirst("https://bigiluu.com/", "");
    }

    if (path.startsWith("http")) {
      return path;
    }

    path = path.replaceAll("\\", "/").replaceAll(RegExp(r'^/+'), "");

    if (!path.contains("/")) {
      path = "uploads/profile_images/$path";
    }

    return "https://bigiluu.com/$path";
  }

  @override
  void initState() {
    super.initState();
    posts = List.from(widget.posts);
    currentPage = widget.initialIndex;
    controller = PageController(initialPage: widget.initialIndex);
    _cardKeys = List.generate(widget.posts.length, (index) => GlobalKey());
    _loadInteractionsLocal();
    fetchUserInteractions();
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? topLabel,
    Color? color,
  }) {
    final bool isHighlighted = color != null;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 16),
              child: Text(
                topLabel,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFB11226),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? color.withOpacity(0.1)
                      : const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isHighlighted
                        ? color.withOpacity(0.3)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: isHighlighted ? color : Colors.grey.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isHighlighted ? color : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        centerTitle: true,
      ),
      body: posts.isEmpty
          ? const Center(
              child: Text("No Posts Available", style: TextStyle(fontSize: 16)),
            )
          : PageView.builder(
              controller: controller,
              scrollDirection: Axis.vertical,
              itemCount: posts.length,
              onPageChanged: (idx) => setState(() => currentPage = idx),
              itemBuilder: (context, index) {
                final post = posts[index];
                final String postIdStr = post['post_id']?.toString() ?? "";
                final String img = post['cover_img'] ?? '';
                final String caption = (post['caption'] ?? '').toString();
                final String hashtag = (post['hastag'] ?? '').toString();
                final String username = (post['username'] ?? 'Storyteller')
                    .toString();
                final String profileImg = (post['profile_image'] ?? '')
                    .toString();
                final int readersCount = post['readers_count'] ?? 0;

                final bool isLiked = likedPosts.contains(postIdStr);
                final bool isSaved = savedPosts.contains(postIdStr);

                // 🏆 Badge Variants Logic
                String ack = (post['acknowledgment'] ?? "")
                    .toString()
                    .toUpperCase();
                String badgeLabel = "";
                List<Color> badgeGradients = [Colors.white, Colors.white];
                Color themeBorderColor = Colors.white;
                Color themeSpineColor = Colors.white.withOpacity(0.2);

                if (ack == "GOAT") {
                  badgeLabel = "GOAT";
                  badgeGradients = [
                    const Color(0xFFFFD700),
                    const Color(0xFFDAA520),
                  ];
                  themeBorderColor = const Color(0xFFFFD700);
                  themeSpineColor = const Color(0xFFFFD700).withOpacity(0.2);
                } else if (ack == "MERSAL") {
                  badgeLabel = "MERSAL";
                  badgeGradients = [
                    const Color(0xFFE0E0E0),
                    const Color(0xFF9E9E9E),
                  ];
                  themeBorderColor = const Color(0xFFC0C0C0);
                  themeSpineColor = const Color(0xFFE0E0E0).withOpacity(0.25);
                } else if (ack == "THERI") {
                  badgeLabel = "THERI";
                  badgeGradients = [
                    const Color(0xFFCD7F32),
                    const Color(0xFF8B4513),
                  ];
                  themeBorderColor = const Color(0xFFCD7F32);
                  themeSpineColor = const Color(0xFFCD7F32).withOpacity(0.2);
                }

                return SingleChildScrollView(
                  child: RepaintBoundary(
                    key: index < _cardKeys.length ? _cardKeys[index] : null,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.05),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Section
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: brandColor.withOpacity(0.2),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.grey.shade100,
                                    backgroundImage: NetworkImage(
                                      profileImg.startsWith("http")
                                          ? profileImg.replaceFirst(
                                              "https://bigiluu.com/https://",
                                              "https://",
                                            )
                                          : fullUrl(profileImg),
                                    ),
                                  ),
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
                                        ),
                                      ),
                                      Text(
                                        "Storyteller",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!widget.isPublicView &&
                                    (widget.title == "My Stories" ||
                                        widget.title == "Post" ||
                                        widget.title == "My Books"))
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
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text("Cancel"),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: brandColor.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.auto_stories_rounded,
                                        color: brandColor,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "$readersCount",
                                        style: const TextStyle(
                                          color: brandColor,
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

                          // Hyper-Realistic 3D Book Cover
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: GestureDetector(
                              onTap: () async {
                                if (_isOpeningPost) return;
                                setState(() => _isOpeningPost = true);

                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FullScreenPostViewer(
                                      pages: extractPages(post['content']),
                                      username: post['username'] ?? "",
                                      profileImage: post['profile_image'] ?? "",
                                      postId: postIdStr,
                                      //summary:
                                      //post['summary']?.toString() ?? "",
                                    ),
                                  ),
                                );

                                if (mounted) {
                                  setState(() => _isOpeningPost = false);
                                }
                              },
                              child: Hero(
                                tag: "post_${post['post_id']}",
                                child: Container(
                                  height: 440,
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                      topLeft: Radius.circular(16),
                                      bottomLeft: Radius.circular(16),
                                    ),
                                    color: const Color(0xFFFDFCF2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 20,
                                        offset: const Offset(8, 8),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Page Edges effect (Home page logic)
                                      Positioned(
                                        right: 0,
                                        top: 8,
                                        bottom: 8,
                                        width: 12,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFDFCF2),
                                            borderRadius:
                                                const BorderRadius.horizontal(
                                                  right: Radius.circular(12),
                                                ),
                                          ),
                                          child: Stack(
                                            children: [
                                              Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceEvenly,
                                                children: List.generate(
                                                  30,
                                                  (i) => Container(
                                                    height: 0.5,
                                                    width: double.infinity,
                                                    color: Colors.black
                                                        .withOpacity(0.04),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.centerLeft,
                                                    end: Alignment.centerRight,
                                                    colors: [
                                                      Colors.black.withOpacity(
                                                        0.08,
                                                      ),
                                                      Colors.transparent,
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // Front Cover
                                      Positioned(
                                        left: 0,
                                        top: -1,
                                        bottom: -1,
                                        right: 8,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topRight: Radius.circular(6),
                                                  bottomRight: Radius.circular(
                                                    6,
                                                  ),
                                                  topLeft: Radius.circular(12),
                                                  bottomLeft: Radius.circular(
                                                    12,
                                                  ),
                                                ),
                                            border: Border.all(
                                              color: themeBorderColor,
                                              width: 2.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.3,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(5, 0),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topRight: Radius.circular(4),
                                                  bottomRight: Radius.circular(
                                                    4,
                                                  ),
                                                  topLeft: Radius.circular(10),
                                                  bottomLeft: Radius.circular(
                                                    10,
                                                  ),
                                                ),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                img.isNotEmpty
                                                    ? Image.network(
                                                        img,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : Container(
                                                        decoration:
                                                            const BoxDecoration(
                                                              gradient: LinearGradient(
                                                                begin: Alignment
                                                                    .topLeft,
                                                                end: Alignment
                                                                    .bottomRight,
                                                                colors: [
                                                                  Color(
                                                                    0xFF2D1B69,
                                                                  ),
                                                                  Color(
                                                                    0xFF11998E,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                        child: const Center(
                                                          child: Icon(
                                                            Icons.book_rounded,
                                                            color:
                                                                Colors.white54,
                                                            size: 64,
                                                          ),
                                                        ),
                                                      ),
                                                // Overlays
                                                Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin:
                                                          Alignment.centerLeft,
                                                      end:
                                                          Alignment.centerRight,
                                                      colors: [
                                                        Colors.black
                                                            .withOpacity(0.65),
                                                        Colors.black
                                                            .withOpacity(0.2),
                                                        Colors.transparent,
                                                        Colors.black
                                                            .withOpacity(0.05),
                                                        Colors.black
                                                            .withOpacity(0.35),
                                                      ],
                                                      stops: const [
                                                        0.0,
                                                        0.04,
                                                        0.2,
                                                        0.96,
                                                        1.0,
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                // Spine shadow
                                                Positioned(
                                                  left: 0,
                                                  top: 0,
                                                  bottom: 0,
                                                  width: 25,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin: Alignment
                                                            .centerLeft,
                                                        end: Alignment
                                                            .centerRight,
                                                        colors: [
                                                          Colors.black
                                                              .withOpacity(0.5),
                                                          Colors.black
                                                              .withOpacity(0.2),
                                                          Colors.black
                                                              .withOpacity(0.4),
                                                          Colors.black
                                                              .withOpacity(0.0),
                                                        ],
                                                        stops: const [
                                                          0.0,
                                                          0.4,
                                                          0.5,
                                                          1.0,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  left: 22,
                                                  top: 0,
                                                  bottom: 0,
                                                  width: 1.2,
                                                  child: Container(
                                                    color: themeSpineColor,
                                                  ),
                                                ),
                                                // Title Styling (Home page logic)
                                                Positioned(
                                                  top: 15,
                                                  left: 10,
                                                  right: 10,
                                                  child: Builder(
                                                    builder: (context) {
                                                      double fs = 15.0;
                                                      String? ff;
                                                      Color tc = Colors.white;
                                                      try {
                                                        double? parsedFs;
                                                        Color? parsedTc;
                                                        String? parsedFf;
                                                        if (post['titleFontSize'] !=
                                                            null)
                                                          parsedFs =
                                                              double.tryParse(
                                                                post['titleFontSize']
                                                                    .toString(),
                                                              );
                                                        if (post['titleColor'] !=
                                                            null) {
                                                          int?
                                                          cv = int.tryParse(
                                                            post['titleColor']
                                                                .toString(),
                                                          );
                                                          if (cv != null)
                                                            parsedTc = Color(
                                                              cv,
                                                            );
                                                        }
                                                        if (post['titleFontFamily'] !=
                                                            null)
                                                          parsedFf =
                                                              post['titleFontFamily']
                                                                  .toString();

                                                        // Content JSON fallback
                                                        dynamic raw =
                                                            post['content'];
                                                        if (raw != null) {
                                                          dynamic dec = raw;
                                                          if (dec is String)
                                                            try {
                                                              dec = jsonDecode(
                                                                dec,
                                                              );
                                                            } catch (_) {}
                                                          if (dec is Map) {
                                                            if (parsedFs ==
                                                                    null &&
                                                                dec['titleFontSize'] !=
                                                                    null)
                                                              parsedFs = double.tryParse(
                                                                dec['titleFontSize']
                                                                    .toString(),
                                                              );
                                                            if (parsedTc ==
                                                                    null &&
                                                                dec['titleColor'] !=
                                                                    null) {
                                                              int?
                                                              cv = int.tryParse(
                                                                dec['titleColor']
                                                                    .toString(),
                                                              );
                                                              if (cv != null)
                                                                parsedTc =
                                                                    Color(cv);
                                                            }
                                                            if (parsedFf ==
                                                                    null &&
                                                                dec['titleFontFamily'] !=
                                                                    null)
                                                              parsedFf =
                                                                  dec['titleFontFamily']
                                                                      .toString();
                                                          }
                                                        }
                                                        if (parsedFs != null)
                                                          fs = (parsedFs * 0.6)
                                                              .clamp(
                                                                12.0,
                                                                45.0,
                                                              );
                                                        if (parsedTc != null)
                                                          tc = parsedTc;
                                                        if (parsedFf != null)
                                                          ff = parsedFf;
                                                      } catch (_) {}
                                                      return Text(
                                                        post['title']
                                                                ?.toString() ??
                                                            '',
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: tc,
                                                          fontSize: fs,
                                                          fontFamily: ff,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          shadows: [
                                                            Shadow(
                                                              color: Colors
                                                                  .black
                                                                  .withOpacity(
                                                                    0.6,
                                                                  ),
                                                              blurRadius: 10,
                                                              offset:
                                                                  const Offset(
                                                                    1,
                                                                    1,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Badge
                                      if (badgeLabel.isNotEmpty)
                                        Positioned(
                                          top: -22,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: badgeGradients,
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.25),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.stars_rounded,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  badgeLabel,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 0.5,
                                                  ),
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
                          ),

                          // Caption & Hashtag
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (caption.isNotEmpty)
                                  Text(
                                    caption,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.w500,
                                      height: 1.5,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (hashtag.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(
                                      hashtag,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: brandColor,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Action row
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _buildActionButton(
                                  icon: Icons.touch_app_rounded,
                                  topLabel: (post['support_count'] ?? 0)
                                      .toString(),
                                  label: "Support",
                                  color: isLiked ? brandColor : null,
                                  onTap: () => toggleLike(postIdStr),
                                ),
                                const SizedBox(width: 8),
                                _buildActionButton(
                                  icon: Icons.share_rounded,
                                  label: "Share",
                                  onTap: () =>
                                      _sharePostAsImage(postIdStr, index),
                                ),
                                const SizedBox(width: 8),
                                _buildActionButton(
                                  icon: isSaved
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_outline_rounded,
                                  label: isSaved ? "Saved" : "Save",
                                  color: isSaved ? brandColor : null,
                                  onTap: () => toggleSave(postIdStr),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
