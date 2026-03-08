import 'dart:convert';
import 'dart:io';
import 'package:bigilu/main.dart';
import 'package:flutter/cupertino.dart';
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
        return domain + "/" + pathPart;
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
          "https://bigiluu.com/api/posts/removeSavedPost/${widget.userId}/$postId",
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
              ? fullUrl(rawCover)
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
                  "https://bigiluu.com/api/posts/singlePost/${p['post_id']}",
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
            if (removedPostId != null && removedPostId is String) {
              setState(() {
                myPosts.removeWhere((p) => p['post_id'] == removedPostId);
                savedPosts.removeWhere((p) => p['post_id'] == removedPostId);
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

                            if (result != null && result is Map) {
                              setState(() {
                                userName = result['username'] ?? userName;
                                _networkImageUrl =
                                    result['profile_image'] ?? _networkImageUrl;
                                _image = null;
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
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WritePage()),
              );

              // 🔥 If draft saved, refresh drafts instantly
              if (result == true) {
                await _loadUserDrafts();
                setState(() {
                  selectedTab =
                      1; // optional → automatically switch to Draft tab
                });
              }
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
                    itemCount: totalPages + 1, // extra cover page
                    onPageChanged: (index) {
                      setState(() {
                        currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      // ==========================
                      // COVER PAGE (index 0)
                      // ==========================
                      if (index == 0) {
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (coverImg != null)
                                Image.network(coverImg!, fit: BoxFit.cover),
                              if (caption != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    8,
                                  ), // reduced top padding
                                  child: Text(
                                    caption!,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              // readers count below caption
                              if (readersCount > 0)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.visibility,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "$readersCount readers",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      // ==========================
                      // CONTENT PAGES (index - 1)
                      // ==========================
                      final page = pages[index - 1];

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
              itemCount: posts.isEmpty ? 1 : posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];

                return SizedBox(
                  height: MediaQuery.of(context).size.height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// POST
                      Flexible(
                        fit: FlexFit.loose,
                        child: Stack(
                          children: [
                            PostContainer(
                              post: post,
                              isSaved: widget.title == "Saved",
                              onSave: () async {
                                if (widget.title == "Saved") {
                                  try {
                                    final response = await http.delete(
                                      Uri.parse(
                                        "https://bigiluu.com/api/posts/removeSavedPost/${widget.userId}/${post['post_id']}",
                                      ),
                                    );

                                    if (response.statusCode == 200) {
                                      setState(() {
                                        posts.removeWhere(
                                          (p) =>
                                              p['post_id'] == post['post_id'],
                                        );
                                      });

                                      Navigator.pop(
                                        context,
                                        post['post_id'].toString(),
                                      );

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
                                if (widget.title == "Post") {
                                  final deleted = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullPostPage(
                                        postId: post['post_id'].toString(),
                                        showDelete: true,
                                      ),
                                    ),
                                  );

                                  if (deleted == true) {
                                    setState(() {
                                      posts.removeWhere(
                                        (p) => p['post_id'] == post['post_id'],
                                      );
                                    });

                                    Navigator.pop(context, post['post_id']);
                                  }
                                } else {
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
                                }
                              },
                            ),

                            /// 🔥 DELETE BUTTON FOR OWN POSTS
                            if (widget.title == "Post")
                              Positioned(
                                top: 10,
                                right: 10,
                                child: GestureDetector(
                                  onTap: () async {
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text("Delete Post"),
                                        content: const Text(
                                          "Are you sure you want to delete this post?",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text("Cancel"),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              Navigator.pop(context);

                                              try {
                                                final response = await http.delete(
                                                  Uri.parse(
                                                    "https://bigiluu.com/api/posts/deletePost/${post['post_id']}",
                                                  ),
                                                );

                                                if (response.statusCode ==
                                                    200) {
                                                  setState(() {
                                                    posts.removeWhere(
                                                      (p) =>
                                                          p['post_id'] ==
                                                          post['post_id'],
                                                    );
                                                  });

                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        "Post deleted successfully",
                                                      ),
                                                    ),
                                                  );

                                                  if (posts.isEmpty) {
                                                    Navigator.pop(context);
                                                  }
                                                }
                                              } catch (e) {
                                                print("Delete error: $e");
                                              }
                                            },
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
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.delete,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      /// CAPTION
                      /// CAPTION
                      if ((post['caption'] ?? "").toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                          child: Text(
                            post['caption'],
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                      /// 🔥 READERS COUNT
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.visibility,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "${post['readers_count'] ?? 0} readers",
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
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
