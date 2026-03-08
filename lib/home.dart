import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:bigilu/PrivacyPage.dart';
import 'package:bigilu/TermsPage.dart';
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
  final String? deepLinkPostId;

  const HomePage({super.key, this.deepLinkPostId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await fetchPosts();

      if (widget.deepLinkPostId != null) {
        openPostFromDeepLink(widget.deepLinkPostId!);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh posts when app comes to foreground
      fetchPosts();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> openPostFromDeepLink(String postId) async {
    try {
      final response = await http
          .get(Uri.parse("https://bigiluu.com/api/posts/getPost/$postId"))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print("⚠️ openPostFromDeepLink timeout");
              throw TimeoutException("Deep link request timed out");
            },
          );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final post = jsonData["data"];

        final pages = extractPages(post['content']);

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenPostViewer(
              pages: pages,
              username: post['username'] ?? "",
              profileImage: post['profile_image'] ?? "",
              postId: post['post_id'], // ✅ ADD
            ),
          ),
        );
      }
    } on TimeoutException catch (e) {
      print("⚠️ Deep link timeout: $e");
    } catch (e) {
      print("Deep link open error: $e");
    }
  }

  List<dynamic> extractPages(dynamic content) {
    try {
      dynamic decoded;

      if (content is String) {
        decoded = jsonDecode(content);
      } else {
        decoded = content;
      }

      if (decoded is Map && decoded.containsKey("pages")) {
        return decoded["pages"] ?? [];
      }

      if (decoded is List) {
        return decoded;
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  Future<void> fetchPosts() async {
    final url = Uri.parse("https://bigiluu.com/api/posts/getAllPosts");

    try {
      print("🔄 Fetching posts from: $url");

      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print("❌ Timeout: Server took too long to respond");
              throw TimeoutException("Request timed out after 10 seconds");
            },
          );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        setState(() {
          posts = jsonData["data"];
          isLoading = false;
        });

        // Debug: Print readers count for each post
        print("✅ DEBUG: Fetched ${posts.length} posts");
        for (int i = 0; i < posts.length; i++) {
          print(
            "📊 Post ${i + 1}: ID=${posts[i]['post_id']} | Readers=${posts[i]['readers_count'] ?? 0}",
          );
        }
      } else {
        // Handle non-200 status codes
        print("❌ Error: API returned status ${response.statusCode}");
        print("❌ Response: ${response.body}");
        setState(() {
          isLoading = false;
        });
      }
    } on TimeoutException catch (e) {
      print("❌ Timeout Error: $e");
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print("❌ Error: $e");
      setState(() {
        isLoading = false;
      });
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

    final url = Uri.parse("https://bigiluu.com/api/posts/savePost");

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId, 'post_id': postId}),
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print("⚠️ toggleSave timeout");
              throw TimeoutException("Save request timed out");
            },
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
    } on TimeoutException {
      print("⚠️ Timeout saving post");
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

  actions: [
    PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.black),
      onSelected: (value) {
        if (value == "terms") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TermsPage()),
          );
        } else if (value == "privacy") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrivacyPage()),
          );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: "terms",
          child: Text("Terms & Conditions"),
        ),
        const PopupMenuItem(
          value: "privacy",
          child: Text("Privacy Policy"),
        ),
      ],
    ),
  ],
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
                        isSaved: savedPosts.contains(postId),
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

                      Container(
                        height: 0.5,
                        color: const Color.fromARGB(255, 0, 0, 0),
                      ),
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
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback? onTap;

  const PostContainer({
    super.key,
    required this.post,

    required this.isSaved,

    required this.onSave,
    this.onTap,
  });

  String fullUrl(String? path) {
    if (path == null || path.isEmpty) {
      return "";
    }

    // ✅ If already a complete URL (http or https), return as-is but ensure HTTPS
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

    // ✅ Clean up path
    path = path.replaceAll("\\", "/").replaceAll(RegExp(r'^/+'), "");

    // ✅ Normalize folder names to lowercase for consistency
    path = path.replaceAll("Uploads", "uploads");
    path = path.replaceAll("Profile_images", "profile_images");
    path = path.replaceAll("Cover_images", "cover_images");
    path = path.replaceAll("Page_images", "page_images");

    // ✅ If only filename, prepend folder
    if (!path.contains("/")) {
      path = "uploads/cover_images/$path";
    }

    // ✅ Return complete HTTPS URL
    return "https://bigiluu.com/$path";
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
    //if (pageList.isEmpty) return const SizedBox();

    print("COVER IMAGE URL: ${fullUrl(post['cover_img'])}");

    final screen = MediaQuery.of(context).size;

    final dynamic rawStyle = post['title_style'];

    final Map<String, dynamic> style = rawStyle == null
        ? {}
        : rawStyle is String
        ? jsonDecode(rawStyle)
        : Map<String, dynamic>.from(rawStyle);

    return GestureDetector(
      onTap: () async {
        try {} catch (e) {
          print("Reader count error: $e");
        }

        final response = await http.get(
          Uri.parse(
            "https://bigiluu.com/api/posts/singlePost/${post['post_id']}",
          ),
        );

        final jsonData = jsonDecode(response.body);
        final pages = jsonData['content'] ?? [];

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenPostViewer(
              pages: pages,
              username: post['username'] ?? "",
              profileImage: post['profile_image'] ?? "",
              postId: post['post_id'],
            ),
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(), // remove forced height
        margin: const EdgeInsets.symmetric(horizontal: 12),
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
                        headers: const {"User-Agent": "Flutter"},
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

            //Divider(thickness: 0.6, color: Colors.grey.shade300),

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
                          headers: const {"User-Agent": "Flutter"},
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            print("IMAGE LOAD ERROR: $error");
                            return const Icon(Icons.broken_image);
                          },
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
                      const Icon(
                        Icons.visibility,
                        size: 18,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "${post['readers_count'] ?? 0}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () {
                          final postUrl =
                              "https://bigiluu.com/post/${post['post_id']}";
                          Share.share(postUrl);
                        },
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

            // Divider(height: 1),
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
  final String postId; // ✅ ADD THIS

  const FullScreenPostViewer({
    super.key,
    required this.pages,
    required this.username,
    required this.profileImage,
    required this.postId, // ✅ ADD
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

    loadLastPage();
    incrementReaderAndVerify();
  }

  Future<void> incrementReaderAndVerify() async {
    try {
      // First, increment the reader count
      print("📊 DEBUG: Incrementing reader for post: ${widget.postId}");

      final incrementResponse = await http
          .post(
            Uri.parse(
              "https://bigiluu.com/api/posts/incrementReader/${widget.postId}",
            ),
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print("⚠️ incrementReader timeout");
              throw TimeoutException("Increment request timed out");
            },
          );

      print(
        "📊 DEBUG: Increment response status: ${incrementResponse.statusCode}",
      );
      print("📊 DEBUG: Increment response body: ${incrementResponse.body}");

      // Then, verify by fetching the updated post data
      await Future.delayed(const Duration(milliseconds: 500));

      final verifyResponse = await http
          .get(
            Uri.parse("https://bigiluu.com/api/posts/getPost/${widget.postId}"),
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print("⚠️ getPost timeout");
              throw TimeoutException("Verify request timed out");
            },
          );

      if (verifyResponse.statusCode == 200) {
        final jsonData = jsonDecode(verifyResponse.body);
        final updatedPost = jsonData["data"];
        print(
          "✅ Verified - Current readers_count in DB: ${updatedPost['readers_count'] ?? 0}",
        );
      }
    } on TimeoutException catch (e) {
      print("⚠️ Timeout in reader count: $e");
    } catch (e) {
      print("❌ Reader count error: $e");
    }
  }

  String fullImageUrl(String? path) {
    if (path == null || path.isEmpty) return "";

    // ✅ If already a complete URL, ensure HTTPS
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

    // ✅ Clean up path
    path = path.replaceAll("\\", "/").replaceAll(RegExp(r'^/+'), "");

    // ✅ Normalize folder names to lowercase for consistency
    path = path.replaceAll("Uploads", "uploads");
    path = path.replaceAll("Profile_images", "profile_images");
    path = path.replaceAll("Cover_images", "cover_images");
    path = path.replaceAll("Page_images", "page_images");

    // ✅ If only filename stored → add correct folder
    if (!path.contains("/")) {
      path = "uploads/page_images/$path";
    }

    return "https://bigiluu.com/$path";
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

  Future<void> loadLastPage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPage = prefs.getInt("reader_${widget.postId}");

    if (savedPage != null && savedPage < widget.pages.length) {
      currentPage = savedPage;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.jumpToPage(savedPage);
      });
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
              onPageChanged: (index) async {
                setState(() {
                  currentPage = index;
                });

                final prefs = await SharedPreferences.getInstance();
                prefs.setInt("reader_${widget.postId}", index);
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
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        width: constraints.maxWidth * 0.95,
                        height: constraints.maxHeight * 0.95,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFF800000),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(2, 2),
                            ),
                          ],
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
                                            headers: const {
                                              "User-Agent": "Flutter",
                                            },
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
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      builder: (context) {
                        return SizedBox(
                          height: 300,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 5,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                ),
                            itemCount: widget.pages.length,
                            itemBuilder: (context, index) {
                              final bool isCurrent = index == currentPage;

                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);

                                  _controller.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFF800000)
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "${index + 1}",
                                    style: TextStyle(
                                      color: isCurrent
                                          ? Colors.white
                                          : Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Page ${currentPage + 1} / ${widget.pages.length}",
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
