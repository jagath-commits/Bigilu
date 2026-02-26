import 'dart:convert';
import 'dart:io';
import 'package:bigilu/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
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

  Widget _draftPlaceholder(String title) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[300],
      child: Center(
        child: Text(
          title.isNotEmpty ? title : "Untitled Draft",
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
    _loadProfileFromBackend();
    _loadUserPosts();
    _loadUserDrafts();
    _loadSavedPosts();
  }

  final String baseUrl = "http://192.168.29.182:3000/api/profile";

  Future<void> _loadUserPosts() async {
    try {
      final response = await http.get(
        Uri.parse(
          "http://192.168.29.182:3000/api/posts/userPosts/${widget.userId}",
        ),
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
        Uri.parse(
          "http://192.168.29.182:3000/api/posts/userDrafts/${widget.userId}",
        ),
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
        Uri.parse(
          "http://192.168.29.182:3000/api/posts/savedPosts/${widget.userId}",
        ),
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
      final response = await http.get(Uri.parse("$baseUrl/${widget.userId}"));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          userName = data['username'] ?? "";
          _networkImageUrl = data['profile_image'] != null
              ? "http://192.168.29.182:3000/${data['profile_image']}"
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
        Uri.parse("http://192.168.29.182:3000/api/draft/deleteDraft/$draftId"),
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

  void _confirmRemoveSaved(String postId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Saved Post"),
        content: const Text("Remove this post from saved?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeSavedPost(postId);
            },
            child: const Text("Remove", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _removeSavedPost(String postId) async {
    try {
      final response = await http.delete(
        Uri.parse(
          "http://192.168.29.182:3000/api/posts/removeSavedPost/${widget.userId}/$postId",
        ),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Removed from saved")));

        _loadSavedPosts(); // 🔥 refresh saved tab
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Failed to remove")));
      }
    } catch (e) {
      print("Remove saved error: $e");
    }
  }

  Widget _buildGridSection() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _getSelectedList().length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.65,
      ),
      itemBuilder: (context, index) {
        final post = _getSelectedList()[index];

        // Drafts
        if (selectedTab == 1) {
          final String? rawCover = post['cover_img'];
          final String coverUrl =
              (rawCover != null && rawCover.toString().isNotEmpty)
              ? "http://192.168.29.182:3000/$rawCover"
              : "";

          final String title = (post['title'] ?? "").toString();

          return Stack(
            children: [
              GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WritePage(
                        draftId: post['post_id'],
                        draftContent: jsonEncode(post['rawContent']),
                        draftCover: post['cover_img'],
                      ),
                    ),
                  );

                  _loadUserDrafts();
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    color: Colors.grey[200],
                    child: Stack(
                      children: [
                        /// 🔥 COVER IMAGE (SAFE)
                        if (coverUrl.isNotEmpty)
                          Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return _draftPlaceholder(title);
                            },
                          )
                        else
                          _draftPlaceholder(title),

                        /// 🔥 TITLE (SAFE)
                        if (title.isNotEmpty)
                          Positioned(
                            bottom: 8,
                            left: 8,
                            right: 8,
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                shadows: [
                                  Shadow(
                                    blurRadius: 4,
                                    color: Colors.black,
                                    offset: Offset(1, 1),
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

              /// DELETE BUTTON
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => _confirmDeleteDraft(post['post_id']),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        // Normal Posts & Saved
        final img = post['cover_img'] ?? "";

        return GestureDetector(
          onTap: () async {
            final postId = post['post_id'];

            // 🔥 Decide which list we are using
            List<Map<String, dynamic>> sourceList = selectedTab == 0
                ? myPosts
                : savedPosts;

            // 🔥 Get clicked index
            int clickedIndex = sourceList.indexWhere(
              (p) => p['post_id'] == postId,
            );

            // 🔥 Fetch full post data for ALL posts
            List<Map<String, dynamic>> fullPosts = [];

            for (var p in sourceList) {
              final response = await http.get(
                Uri.parse(
                  "http://192.168.29.182:3000/api/posts/singlePost/${p['post_id']}",
                ),
              );

              if (response.statusCode == 200) {
                fullPosts.add(jsonDecode(response.body));
              }
            }

            // 🔥 Open feed style viewer starting from clicked post
            final removedPostId = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileFeedViewer(
                  posts: fullPosts,
                  initialIndex: clickedIndex < 0 ? 0 : clickedIndex,
                  title: selectedTab == 0 ? "Post" : "Saved",
                  userId: widget.userId,
                ),
              ),
            );

            // 🔥 IF POST REMOVED FROM SAVED TAB
            if (removedPostId != null) {
              setState(() {
                // 🔥 If in Our Posts tab
                if (selectedTab == 0) {
                  myPosts.removeWhere((p) => p['post_id'] == removedPostId);
                }

                // 🔥 If in Saved tab
                if (selectedTab == 2) {
                  savedPosts.removeWhere((p) => p['post_id'] == removedPostId);
                }
              });
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                img.isNotEmpty
                    ? Image.network(
                        img,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image),
                          );
                        },
                      )
                    : Container(color: Colors.grey[300]),

                /// 🔥 TITLE OVER IMAGE
                if ((post['title'] ?? "").toString().isNotEmpty)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Text(
                      post['title'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: Colors.black,
                            offset: Offset(1, 1),
                          ),
                        ],
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
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),

            // Make top section scroll-safe
            Expanded(
              child: Column(
                children: [
                  // Username
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  _buildAvatar(),

                  const SizedBox(height: 15),

                  Text(
                    "${myPosts.length}",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text("Posts"),

                  const SizedBox(height: 20),

                  // Buttons (responsive)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),

                        ElevatedButton(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditProfilePage(userId: widget.userId),
                              ),
                            );

                            if (result != null) {
                              setState(() {
                                userName = result['username'] ?? userName;
                                _image = result['image'];
                                _networkImageUrl = result['imageUrl'];
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF800000),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: const Text(
                            "Edit Profile",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),

                        const SizedBox(width: 8),

                        ElevatedButton(
                          onPressed: () => Share.share("Check out my profile!"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF800000),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: const Text(
                            "Share Profile",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),

                        const SizedBox(width: 8),

                        ElevatedButton(
                          onPressed: _confirmLogout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF800000),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: const Text(
                            "Logout",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),

                        const SizedBox(width: 8),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Divider(),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildTab("Our Posts", 0),
                      _buildTab("Draft", 1),
                      _buildTab("Saved", 2),
                    ],
                  ),
                  const Divider(),

                  // Grid Section
                  Expanded(child: _buildGridSection()),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  // ============================
  // Avatar
  // ============================
  Widget _buildAvatar() {
    ImageProvider provider;

    if (_image != null) {
      provider = FileImage(_image!);
    } else if (_networkImageUrl != null) {
      provider = NetworkImage(_networkImageUrl!);
    } else {
      provider = const NetworkImage('https://i.stack.imgur.com/l60Hf.png');
    }

    return CircleAvatar(radius: 50, backgroundImage: provider);
  }

  // ============================
  // Tabs
  // ============================
  List<Map<String, dynamic>> _getSelectedList() {
    if (selectedTab == 0) return myPosts;
    if (selectedTab == 1) return draftPosts;
    return savedPosts;
  }

  Widget _buildTab(String title, int index) {
    return GestureDetector(
      onTap: () => setState(() => selectedTab = index),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: selectedTab == index
              ? FontWeight.bold
              : FontWeight.normal,
          color: selectedTab == index ? const Color(0xFF800000) : Colors.grey,
        ),
      ),
    );
  }

  // ============================
  // Bottom Navigation
  // ============================
  Widget _buildBottomNavigationBar(BuildContext context) {
    return BottomAppBar(
      height: 60,
      color: const Color(0xFF800000),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () {},
          ), // Already on profile
          IconButton(
            icon: const Icon(Icons.tag, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HashtagPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HomePage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WritePage()),
              );
            },
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
      final response = await http.get(
        Uri.parse(
          "http://192.168.29.182:3000/api/posts/singlePost/${widget.postId}",
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          coverImg = data['cover_img'];
          caption = data['caption'];
          pages = data['content'];
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
        Uri.parse(
          "http://192.168.29.182:3000/api/posts/deletePost/${widget.postId}",
        ),
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
    final totalPages = pages.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Post"),
        actions: widget.showDelete
            ? [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _confirmDelete,
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // ==========================
                  // PAGE VIEW
                  // ==========================
                  PageView.builder(
                    controller: _pageController,
                    itemCount: totalPages,
                    onPageChanged: (index) {
                      setState(() {
                        currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      // ==========================
                      // COVER PAGE (index 0)
                      // ==========================
                      /*if (index == 0) {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            if (coverImg != null)
                              Image.network(coverImg!, fit: BoxFit.cover),
                            if (caption != null)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  caption!,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }*/

                      // ==========================
                      // CONTENT PAGES (index - 1)
                      // ==========================
                      final page = pages[index];

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...(page['blocks'] as List? ?? []).map<Widget>((
                              block,
                            ) {
                              if (block['type'] == "text") {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    block['text'] ?? "",
                                    style: TextStyle(
                                      fontSize: (page['fontSize'] ?? 16)
                                          .toDouble(),
                                      color: _parseColor(page['fontColor']),
                                      fontFamily: page['fontFamily'],
                                    ),
                                  ),
                                );
                              }

                              if (block['type'] == "image" &&
                                  block['image'] != null &&
                                  block['image'].toString().isNotEmpty) {
                                // 🔥 DEBUG: print image URL coming from backend
                                print("FULL POST IMAGE URL: ${block['image']}");

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Image.network(
                                    block['image'],
                                    fit: BoxFit.contain,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Text(
                                        "Image not found",
                                        style: TextStyle(color: Colors.red),
                                      );
                                    },
                                  ),
                                );
                              }

                              return const SizedBox();
                            }).toList(),
                          ],
                        ),
                      );
                    },
                  ),

                  // ==========================
                  // PAGE NUMBER INDICATOR
                  // ==========================
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${currentPage + 1} / $totalPages",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
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
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];

                return SizedBox(
                  height: MediaQuery.of(context).size.height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// POST
                      Expanded(
                        child: PostContainer(
                          post: post,
                          isLiked: false,
                          isSaved: widget.title == "Saved",
                          onLike: () {},
                          onSave: () async {
                            if (widget.title == "Saved") {
                              try {
                                final response = await http.delete(
                                  Uri.parse(
                                    "http://192.168.29.182:3000/api/posts/removeSavedPost/${widget.userId}/${post['post_id']}",
                                  ),
                                );

                                if (response.statusCode == 200) {
                                  setState(() {
                                    posts.removeWhere(
                                      (p) => p['post_id'] == post['post_id'],
                                    );
                                  });

                                  // 🔥 RETURN REMOVED POST ID TO PREVIOUS PAGE
                                  Navigator.pop(context, post['post_id']);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Removed from saved"),
                                    ),
                                  );
                                }
                              } catch (e) {
                                print("Error removing saved: $e");
                              }
                            }
                          },
                          onTap: () async {
                            final deleted = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullPostPage(
                                  postId: post['post_id'].toString(),
                                  showDelete: widget.title == "Post",
                                  //openFirstContent: true,
                                ),
                              ),
                            );

                            // 🔥 IF POST DELETED
                            if (deleted == true) {
                              setState(() {
                                posts.removeWhere(
                                  (p) => p['post_id'] == post['post_id'],
                                );
                              });

                              // 🔥 RETURN ID BACK TO PROFILE PAGE
                              Navigator.pop(context, post['post_id']);
                            }
                          },
                        ),
                      ),

                      /// CAPTION
                      if ((post['caption'] ?? "").toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                          child: Text(
                            post['caption'],
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                      /// HASHTAG
                      if ((post['hastag'] ?? "").toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: Text(
                            post['hastag'],
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.blue,
                            ),
                          ),
                        ),

                      Divider(
                        thickness: 0.6,
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
