import 'dart:convert';
import 'dart:io' show Platform;
import 'package:bigilu/hashtag.dart';
import 'package:bigilu/profile1.dart';
import 'package:bigilu/write.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Set<String> likedPosts = {};
  Set<String> savedPosts = {};
  List posts = [];
  bool isLoading = true;

  Future<String?> getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchPosts(); // move API call here instead of direct initState
    });
  }

  Future<void> fetchPosts() async {
    final url = Uri.parse("http://192.168.29.182:3000/api/posts/getAllPosts");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        setState(() {
          posts = jsonData["data"];
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  void toggleLike(String postId) {
    setState(() {
      likedPosts.contains(postId)
          ? likedPosts.remove(postId)
          : likedPosts.add(postId);
    });
  }

  void toggleSave(String postId) async {
    String? userId = await getUserId();
    if (userId == null) return;

    final url = Uri.parse("http://192.168.29.182:3000/api/posts/savePost");

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'post_id': postId}),
      );

      if (response.statusCode == 200) {
        setState(() {
          savedPosts.contains(postId)
              ? savedPosts.remove(postId)
              : savedPosts.add(postId);
        });
      } else {
        print("Failed to save post: ${response.body}");
      }
    } catch (e) {
      print("Error saving post: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (Platform.isAndroid) {
          SystemNavigator.pop();
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
          title: Image.asset("assets/images/bigilu_logo21.png", height: 50),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: posts.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Image.asset(
                      "assets/images/tvk.webp",
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    );
                  }

                  final post = posts[index - 1];
                  final postId = post['post_id'];

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PostContainer(
                        post: post,
                        isLiked: likedPosts.contains(postId),
                        isSaved: savedPosts.contains(postId),
                        onLike: () => toggleLike(postId),
                        onSave: () => toggleSave(postId),
                      ),

                      // ===============================
                      // CAPTION + HASHTAG
                      // ===============================
                      if ((post['caption'] ?? "").toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                          child: Align(
                            alignment: Alignment.centerLeft, // ✅ FORCE LEFT
                            child: Text(
                              post['caption'],
                              textAlign: TextAlign.left, // ✅ FORCE LEFT
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      if ((post['hastag'] ?? "").toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                          child: Align(
                            alignment: Alignment.centerLeft, // ✅ FORCE LEFT
                            child: Text(
                              post['hastag'],
                              textAlign: TextAlign.left, // ✅ FORCE LEFT
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),

                      Container(height: 0.5, color: Colors.grey.shade300),
                    ],
                  );
                },
              ),
        bottomNavigationBar: _buildBottomNavigationBar(context),
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return SafeArea(
      top: false, // 🔥 important (only protect bottom)
      child: BottomAppBar(
        height: 60,
        color: const Color(0xFF800000),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(Icons.person, color: Colors.white),
              onPressed: () async {
                String? userId = await getUserId();
                if (userId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfilePage(userId: userId),
                    ),
                  );
                }
              },
            ),
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
              onPressed: () {},
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
      ),
    );
  }
}

/* ---------------- POST CARD ---------------- */

class PostContainer extends StatelessWidget {
  final Map post;
  final bool isLiked;
  final bool isSaved;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback? onTap;

  const PostContainer({
    super.key,
    required this.post,
    required this.isLiked,
    required this.isSaved,
    required this.onLike,
    required this.onSave,
    this.onTap,
  });

  String fullUrl(String? path) {
    if (path == null || path.isEmpty) {
      return "";
    }

    if (path.startsWith("http")) return path;

    if (!path.contains("/")) {
      path = "uploads/cover_images/$path";
    }

    return "http://192.168.29.182:3000/$path";
  }

  List<dynamic> list_pages() {
    final content = post['content'];

    if (content == null) return [];

    dynamic decoded;

    try {
      if (content is String && content.trim().startsWith('{')) {
        decoded = jsonDecode(content);
      } else if (content is String && content.trim().startsWith('[')) {
        decoded = jsonDecode(content);
      } else {
        decoded = content;
      }
    } catch (e) {
      debugPrint("JSON parse error: $e");
      return [];
    }

    if (decoded is Map && decoded.containsKey("pages")) {
      return decoded["pages"] ?? [];
    }

    if (decoded is List) {
      return decoded;
    }

    return [];
  }

  String extractTitle() {
    return post['title']?.toString() ?? "";
  }

  @override
  Widget build(BuildContext context) {
    final pageList = list_pages();
    if (pageList.isEmpty) return const SizedBox();

    final screen = MediaQuery.of(context).size;

    final dynamic rawStyle = post['title_style'];

    final Map<String, dynamic> style = rawStyle == null
        ? {}
        : rawStyle is String
        ? jsonDecode(rawStyle)
        : Map<String, dynamic>.from(rawStyle);

    return GestureDetector(
      onTap:
          onTap ??
          () {
            final pages = list_pages();
            if (pages.isEmpty) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenPostViewer(
                  pages: pages,
                  username: post['username'] ?? "",
                  profileImage: post['profile_image'] ?? "",
                ),
              ),
            );
          },
      child: Container(
        constraints: const BoxConstraints(), // remove forced height
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// USER ROW
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey.shade300,
                    child: ClipOval(
                      child: Image.network(
                        fullUrl(post['profile_image'] ?? ''),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: post['username'] ?? "",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const TextSpan(
                            text: " has published a book",
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Divider(thickness: 0.6, color: Colors.grey.shade300),

            /// COVER
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6, // fixed height
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.network(
                          fullUrl(post['cover_img']),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade300,
                            child: const Center(
                              child: Icon(Icons.broken_image, size: 40),
                            ),
                          ),
                        ),
                      ),

                      Positioned.fill(
                        child: Container(color: Colors.black.withOpacity(0.1)),
                      ),

                      Positioned(
                        top: 30,
                        left: 16,
                        right: 16,
                        child: Text(
                          extractTitle(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: (style['fontSize'] is num
                                ? style['fontSize'].toDouble()
                                : 24.0),
                            color: Color(
                              style['color'] is int
                                  ? style['color']
                                  : Colors.white.value,
                            ),
                            fontFamily: style['fontFamily'] ?? "Roboto",
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            /// ACTIONS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? Colors.red : Colors.black,
                        ),
                        onPressed: onLike,
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () => Share.share("Check out my profile!"),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(
                      isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: isSaved ? Colors.blue : Colors.black,
                    ),
                    onPressed: onSave,
                  ),
                ],
              ),
            ),

            Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

/* ---------------- FULL SCREEN TEXT VIEW ---------------- */

class FullScreenPostViewer extends StatefulWidget {
  final List pages;
  final String username;
  final String profileImage;

  const FullScreenPostViewer({
    super.key,
    required this.pages,
    required this.username,
    required this.profileImage,
  });
  @override
  State<FullScreenPostViewer> createState() => _FullScreenPostViewerState();
}

class _FullScreenPostViewerState extends State<FullScreenPostViewer> {
  int currentPage = 0;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  String fullImageUrl(String? path) {
    if (path == null || path.isEmpty) return "";

    // If backend already sends full URL
    if (path.startsWith("http")) return path;

    // Remove leading slash if any
    if (path.startsWith("/")) {
      path = path.substring(1);
    }

    // If only filename stored → add correct folder
    if (!path.contains("/")) {
      path = "uploads/page_images/$path";
    }

    return "http://192.168.29.182:3000/$path";
  }

  Color parseColor(dynamic value) {
    try {
      if (value == null) return Colors.black;

      if (value is int) return Color(value);

      if (value is String) {
        return Color(int.parse(value));
      }

      return Colors.black;
    } catch (_) {
      return Colors.black;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // ✅ NEW APPBAR DESIGN
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey.shade300,
              child: ClipOval(
                child: Image.network(
                  fullImageUrl(widget.profileImage ?? ''),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.person, size: 16);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.username,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.pages.length,
              onPageChanged: (index) {
                setState(() {
                  currentPage = index;
                });
              },
              itemBuilder: (context, index) {
                final page = widget.pages[index];
                final blocks = page['blocks'] ?? [];

                final fontSize = (page['fontSize'] ?? 16).toDouble();
                final fontFamily = page['fontFamily'] ?? "Roboto";
                final fontColor = parseColor(
                  page['fontColor'] ?? Colors.black.value,
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: blocks.map<Widget>((block) {
                            if (block['type'] == 'text' &&
                                block['text'] != null) {
                              return Text(
                                block['text'],
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontFamily: fontFamily,
                                  color: fontColor,
                                ),
                              );
                            }

                            if (block['type'] == 'image' &&
                                block['image'] != null) {
                              final imageUrl = fullImageUrl(block['image']);

                              return SizedBox(
                                height: constraints.maxHeight * 0.6,
                                child: LayoutBuilder(
                                  builder: (context, box) {
                                    final double dx =
                                        (block['imagePosX'] ?? 0.5).toDouble();
                                    final double dy =
                                        (block['imagePosY'] ?? 0.0).toDouble();

                                    return Stack(
                                      children: [
                                        Positioned(
                                          left: dx * box.maxWidth,
                                          top: dy * box.maxHeight,
                                          child: Image.network(
                                            imageUrl,
                                            width: (block['imageWidth'] ?? 200)
                                                .toDouble(),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              );
                            }

                            return const SizedBox();
                          }).toList(),
                        ),
                      ),
                    );
                  },
                );
              },
            ),

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
                  "${currentPage + 1} / ${widget.pages.length}",
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
