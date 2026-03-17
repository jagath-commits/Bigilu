import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io' show Platform;
import 'package:bigilu/PrivacyPage.dart';
import 'package:bigilu/TermsPage.dart';
import 'package:bigilu/hashtag.dart';
import 'package:bigilu/profile1.dart';
import 'package:bigilu/write.dart';
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
            const Duration(seconds: 25),
            onTimeout: () {
              print("❌ Timeout: Server took too long to respond");
              throw TimeoutException("Request timed out after 25 seconds");
            },
          );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        setState(() {
          posts = jsonData["data"] ?? [];
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
        backgroundColor: const Color(0xFFF8F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 2,
          toolbarHeight: 75,
          automaticallyImplyLeading: false,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
          leadingWidth: 230,
          title: null,
          leading: Transform.translate(
            offset: const Offset(-20, 0),
            child: Padding(
              padding: const EdgeInsets.only(left: 0),
              child: Image.asset(
                "assets/images/bigilu_logo21.png",
                fit: BoxFit.contain,
                height: 70,
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFB11226),
                          const Color(0xFF8A0C20),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFB11226).withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  offset: const Offset(0, 55),
                  elevation: 16,
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
                    PopupMenuItem(
                      value: "terms",
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2196F3).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.description_rounded,
                              color: Color(0xFF2196F3),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            "Terms & Conditions",
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: "privacy",
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2196F3).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.privacy_tip_rounded,
                              color: Color(0xFF2196F3),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            "Privacy Policy",
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFB11226)),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  final post = posts[index];
                  final postId = post['post_id'];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: PostContainer(
                      post: post,
                      isLiked: likedPosts.contains(postId),
                      onLike: () => toggleLike(postId),
                      isSaved: savedPosts.contains(postId),
                      onSave: () => toggleSave(postId),
                    ),
                  );
                },
              ),
        bottomNavigationBar: _buildBottomNavigationBar(context),
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: const Color(0xFFB11226), width: 2.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _build3DNavItem(
                context,
                Icons.home_rounded,
                "Home",
                () {},
                isActive: true,
              ),
              _build3DNavItem(context, Icons.explore_rounded, "Explore", () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HashtagPage()),
                );
              }, isActive: false),
              _build3DNavItem(context, Icons.edit_rounded, "Write", () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WritePage()),
                );
              }, isActive: false),
              _build3DNavItem(
                context,
                Icons.person_rounded,
                "Profile",
                () async {
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
                isActive: false,
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
    double iconSize = screenWidth < 360 ? 22 : 26;
    double fontSize = screenWidth < 360 ? 9 : 10;

    Color activeColor = const Color(0xFFB11226);
    Color inactiveColor = Colors.grey.shade600;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        splashColor: activeColor.withOpacity(0.15),
        highlightColor: activeColor.withOpacity(0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: isActive
              ? BoxDecoration(
                  color: activeColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activeColor.withOpacity(0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                )
              : BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? activeColor : inactiveColor,
                size: iconSize,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? activeColor : inactiveColor,
                  fontSize: fontSize,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                  fontFamily: 'Roboto',
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
        return "$domain/$pathPart";
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
    const brandColor = Color(0xFFB11226);
    final caption = post['caption']?.toString() ?? "";
    final hashtag = post['hastag']?.toString() ?? "";

    final screenWidth = MediaQuery.of(context).size.width;
    double paddingHorizontal = screenWidth < 360 ? 12 : 20;

    final String postIdStr = post['post_id']?.toString() ?? "";

    // 🏆 Badge Variants Logic
    final int variantNum = (postIdStr.hashCode).abs() % 3;

    String badgeLabel = "GOAT";
    List<Color> badgeGradients = [
      const Color(0xFFFFD700),
      const Color(0xFFDAA520),
    ];
    Color themeBorderColor = const Color(0xFFFFD700);
    Color themeSpineColor = const Color(0xFFFFD700).withOpacity(0.2);

    if (variantNum == 0) {
      // Gold Variety (GOAT)
      badgeLabel = "GOAT";
      badgeGradients = [const Color(0xFFFFD700), const Color(0xFFDAA520)];
      themeBorderColor = const Color(0xFFFFD700);
      themeSpineColor = const Color(0xFFFFD700).withOpacity(0.2);
    } else if (variantNum == 1) {
      // Silver Variety (MERSAL)
      badgeLabel = "MERSAL";
      badgeGradients = [
        const Color(0xFFE0E0E0),
        const Color(0xFF9E9E9E),
        const Color(0xFFE0E0E0),
      ];
      themeBorderColor = const Color(0xFFC0C0C0);
      themeSpineColor = const Color(0xFFE0E0E0).withOpacity(0.25);
    } else {
      // Bronze Variety (THERI)
      badgeLabel = "THERI";
      badgeGradients = [const Color(0xFFCD7F32), const Color(0xFF8B4513)];
      themeBorderColor = const Color(0xFFCD7F32);
      themeSpineColor = const Color(0xFFCD7F32).withOpacity(0.2);
    }

    return GestureDetector(
      onTap: () async {
        try {
          final response = await http
              .get(
                Uri.parse(
                  "https://bigiluu.com/api/posts/singlePost/$postIdStr",
                ),
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final jsonData = jsonDecode(response.body);
            final rawContent = jsonData['content'];

            List<dynamic> pages = [];
            if (rawContent != null) {
              if (rawContent is String) {
                try {
                  final decoded = jsonDecode(rawContent);
                  if (decoded is List) {
                    pages = decoded;
                  } else if (decoded is Map && decoded.containsKey('pages')) {
                    pages = decoded['pages'] ?? [];
                  }
                } catch (e) {
                  debugPrint("Error decoding post content: $e");
                }
              } else if (rawContent is List) {
                pages = rawContent;
              }
            }

            if (!context.mounted) return;

            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenPostViewer(
                  pages: pages,
                  username: post['username']?.toString() ?? "",
                  profileImage: post['profile_image']?.toString() ?? "",
                  postId: postIdStr,
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint("Error loading single post: $e");
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.black.withOpacity(0.05), // Reverted to subtle gray
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
              padding: EdgeInsets.all(paddingHorizontal),
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
                        fullUrl(post['profile_image'] ?? ''),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post['username'] ?? "Bigiluu Member",
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          "Storyteller",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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
                        const SizedBox(width: 6),
                        Text(
                          "${post['readers_count']?.toString() ?? "0"}",
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
              padding: EdgeInsets.symmetric(horizontal: paddingHorizontal),
              child: Hero(
                tag: "post_${post['post_id']}",
                child: Container(
                  height: 440, // Reduced height for more balanced feed
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                    color: const Color(
                      0xFFFDFCF2,
                    ), // Creamy paper color instead of dark
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 20,
                        offset: const Offset(8, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none, // Allow badge to overflow
                    children: [
                      // Page Edges Effect (Simulating stacked pages on the right)
                      Positioned(
                        right: 0,
                        top: 8,
                        bottom: 8,
                        width: 12,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDFCF2),
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(12),
                            ),
                          ),
                          child: Stack(
                            children: [
                              // Subtle page line grain
                              Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: List.generate(
                                  30,
                                  (i) => Container(
                                    height: 0.5,
                                    width: double.infinity,
                                    color: Colors.black.withOpacity(0.04),
                                  ),
                                ),
                              ),
                              // Inset shadow for page depth
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.black.withOpacity(0.08),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Front Cover (Offset slightly to show page edges)
                      Positioned(
                        left: 0,
                        top: -1,
                        bottom: -1,
                        right: 8, // Thinner gap for more realistic page edge
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(6),
                              bottomRight: Radius.circular(6),
                              topLeft: Radius.circular(12), // Rounder spine
                              bottomLeft: Radius.circular(12),
                            ),
                            border: Border.all(
                              color: themeBorderColor, // Dynamic border color
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(5, 0),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(4),
                              bottomRight: Radius.circular(4),
                              topLeft: Radius.circular(10),
                              bottomLeft: Radius.circular(10),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Cover Image — guard against empty/null URL
                                Builder(builder: (context) {
                                  final coverUrl = fullUrl(post['cover_img']);
                                  if (coverUrl.isEmpty) {
                                    // No cover image — show nice placeholder
                                    return Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFF2D1B69),
                                            Color(0xFF11998E),
                                          ],
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.book_rounded,
                                          color: Colors.white54,
                                          size: 64,
                                        ),
                                      ),
                                    );
                                  }
                                  return Image.network(
                                    coverUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        color: const Color(0xFFF8F8F8),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: brandColor,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFF2D1B69),
                                            Color(0xFF11998E),
                                          ],
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.book_rounded,
                                          color: Colors.white54,
                                          size: 64,
                                        ),
                                      ),
                                    ),
                                  );
                                }),

                                // Premium Overlay (Subtle gradient and leather texture look)
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: [
                                        Colors.black.withOpacity(0.65),
                                        Colors.black.withOpacity(0.2),
                                        Colors.transparent,
                                        Colors.black.withOpacity(0.05),
                                        Colors.black.withOpacity(0.35),
                                      ],
                                      stops: const [0.0, 0.04, 0.2, 0.96, 1.0],
                                    ),
                                  ),
                                ),

                                // Realistic Spine Curve (Gradient Shadow)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 25,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          Colors.black.withOpacity(0.5),
                                          Colors.black.withOpacity(0.2),
                                          Colors.black.withOpacity(0.4),
                                          Colors.black.withOpacity(0.0),
                                        ],
                                        stops: const [0.0, 0.4, 0.5, 1.0],
                                      ),
                                    ),
                                  ),
                                ),
                                // Dynamic Spine Accent
                                Positioned(
                                  left: 22,
                                  top: 0,
                                  bottom: 0,
                                  width: 1.2,
                                  child: Container(color: themeSpineColor),
                                ),

                                // 📖 Book Title — bottom of cover
                                if ((post['title']?.toString() ?? '').isNotEmpty)
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Builder(builder: (context) {
                                      // Parse title style from content JSON
                                      double fs = 13.0;
                                      String? ff;
                                      Color tc = Colors.white;
                                      try {
                                        final raw = post['content'];
                                        if (raw != null) {
                                          dynamic dec = raw is String ? jsonDecode(raw) : raw;
                                          if (dec is Map) {
                                            final s = double.tryParse(dec['titleFontSize']?.toString() ?? '');
                                            if (s != null) fs = (s * 0.38).clamp(9.0, 17.0);
                                            ff = dec['titleFontFamily']?.toString();
                                            final c = int.tryParse(dec['titleColor']?.toString() ?? '');
                                            if (c != null) tc = Color(c);
                                          }
                                        }
                                      } catch (_) {}
                                      return Container(
                                        padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              Colors.black.withOpacity(0.85),
                                              Colors.black.withOpacity(0.4),
                                              Colors.transparent,
                                            ],
                                            stops: const [0.0, 0.6, 1.0],
                                          ),
                                        ),
                                        child: Text(
                                          post['title']?.toString() ?? '',
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: tc,
                                            fontSize: fs,
                                            fontFamily: ff,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.2,
                                            height: 1.3,
                                            shadows: const [
                                              Shadow(
                                                color: Colors.black,
                                                blurRadius: 10,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ✅ Dynamic Badge (Refined)
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
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
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

            // Caption Section
            Padding(
              padding: EdgeInsets.fromLTRB(
                paddingHorizontal,
                20,
                paddingHorizontal,
                0,
              ),
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

            // Actions
            Padding(
              padding: EdgeInsets.fromLTRB(
                paddingHorizontal,
                24, // Increased top space to prevent touching post area
                paddingHorizontal,
                24, // Added bottom padding inside the card
              ),
              child: Row(
                children: [
                  _buildActionButton(
                    icon: Icons.touch_app_rounded,
                    label: "Support",
                    color: isLiked ? brandColor : null,
                    onTap: onLike,
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.share_rounded,
                    label: "Share",
                    onTap: () =>
                        Share.share("https://bigiluu.com/post/$postIdStr"),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    label: isSaved ? "Saved" : "Save",
                    color: isSaved ? brandColor : null,
                    onTap: onSave,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final bool isHighlighted = color != null;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
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
                Icon(icon, size: 18, color: color ?? const Color(0xFF6E6E73)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color ?? const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
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
  bool readerCounted = false;

  // Reader Settings (Synced with uploaded UI)
  double _fontSize = 18.0;
  String _fontFamily = "Lora";
  double _lineHeight = 1.6;
  TextAlign _alignment = TextAlign.left;
  double _letterSpacing = 0.2;
  double _horizontalPadding = 50.0;
  String _currentTheme = "Sepia"; // Light, Sepia, Dark

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _loadSettings();
    loadLastPage();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble("reader_font_size") ?? 18.0;
      _fontFamily = prefs.getString("reader_font_family") ?? "Lora";
      _lineHeight = prefs.getDouble("reader_line_height") ?? 1.6;
      _letterSpacing = prefs.getDouble("reader_letter_spacing") ?? 0.2;
      _horizontalPadding = prefs.getDouble("reader_horizontal_padding") ?? 50.0;
      _currentTheme = prefs.getString("reader_theme") ?? "Sepia";
      String align = prefs.getString("reader_alignment") ?? "left";
      if (align == "center") {
        _alignment = TextAlign.center;
      } else if (align == "justify") {
        _alignment = TextAlign.justify;
      } else {
        _alignment = TextAlign.left;
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble("reader_font_size", _fontSize);
    await prefs.setString("reader_font_family", _fontFamily);
    await prefs.setDouble("reader_line_height", _lineHeight);
    await prefs.setDouble("reader_letter_spacing", _letterSpacing);
    await prefs.setDouble("reader_horizontal_padding", _horizontalPadding);
    await prefs.setString("reader_theme", _currentTheme);
    String alignStr = "left";
    if (_alignment == TextAlign.center) alignStr = "center";
    if (_alignment == TextAlign.justify) alignStr = "justify";
    await prefs.setString("reader_alignment", alignStr);
  }

  Color _getBackgroundColor() {
    switch (_currentTheme) {
      case "Dark":
        return const Color(0xFF121212);
      case "Sepia":
        return const Color(0xFFE5DED0);
      case "Light":
        return const Color(0xFFF0F0F0);
      default:
        return const Color(0xFFE5DED0);
    }
  }

  Color _getPaperColor() {
    switch (_currentTheme) {
      case "Dark":
        return const Color(0xFF1E1E1E);
      case "Sepia":
        return const Color(0xFFFDFBF7);
      case "Light":
        return const Color(0xFFFFFFFF);
      default:
        return const Color(0xFFFDFBF7);
    }
  }

  Color _getTextColor() {
    switch (_currentTheme) {
      case "Dark":
        return const Color(0xFFE0E0E0);
      default:
        return const Color(0xFF2C2C2C);
    }
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
        return "$domain/$pathPart";
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
    const brandColor = Color(0xFFB11226);
    final themeBg = _getBackgroundColor();
    final paperColor = _getPaperColor();
    final textColor = _getTextColor();

    return Scaffold(
      backgroundColor: themeBg,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [themeBg.withOpacity(0.9), themeBg.withOpacity(0.0)],
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: textColor.withOpacity(0.8),
                  size: 26,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            title: Column(
              children: [
                Text(
                  "Reading",
                  style: TextStyle(
                    color: textColor.withOpacity(0.9),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    fontFamily: 'serif',
                  ),
                ),
                Text(
                  "Page ${currentPage + 1} of ${widget.pages.length + 1}",
                  style: TextStyle(
                    color: textColor.withOpacity(0.5),
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.text_format_rounded,
                  color: textColor.withOpacity(0.8),
                  size: 24,
                ),
                onPressed: () => _showSettingsSheet(context),
              ),
              IconButton(
                icon: Icon(
                  Icons.ios_share_rounded,
                  color: textColor.withOpacity(0.8),
                  size: 22,
                ),
                onPressed: () {
                  Share.share(
                    "Read this post on Bigiluu: https://bigiluu.com/post/${widget.postId}",
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Atmosphere (Subtle Vignette)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Colors.white.withOpacity(0.02),
                    Colors.black.withOpacity(0.05),
                  ],
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                const SizedBox(height: 100), // Space for AppBar
                // Immersive Progress Indicator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (currentPage + 1) / (widget.pages.length + 1),
                      backgroundColor: textColor.withOpacity(0.05),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        brandColor.withOpacity(0.6),
                      ),
                      minHeight: 2,
                    ),
                  ),
                ),

                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: widget.pages.length + 1,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) async {
                      setState(() => currentPage = index);
                      final prefs = await SharedPreferences.getInstance();
                      prefs.setInt("reader_${widget.postId}", index);

                      if (!readerCounted && index >= 2) {
                        String key = "reader_counted_${widget.postId}";
                        bool alreadyCounted = prefs.getBool(key) ?? false;
                        if (!alreadyCounted) {
                          readerCounted = true;
                          await incrementReaderAndVerify();
                          prefs.setBool(key, true);
                        }
                      }
                    },
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildSummaryPage(paperColor, textColor);
                      }

                      final page = widget.pages[index - 1];
                      final blocks = page['blocks'] ?? [];

                      return SizedBox.expand(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 75),
                          decoration: BoxDecoration(
                            color: paperColor,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              // Main Page Shadow
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  _currentTheme == "Dark" ? 0.5 : 0.2,
                                ),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                                spreadRadius: -8,
                              ),
                              // Side Page Stack Effect (Subtle)
                              BoxShadow(
                                color: paperColor.withOpacity(0.8),
                                offset: const Offset(4, 4),
                                blurRadius: 0,
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                offset: const Offset(5, 5),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Subtle Paper Texture
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      image: DecorationImage(
                                        image: const NetworkImage(
                                          "https://www.transparenttextures.com/patterns/clean-gray-paper.png",
                                        ),
                                        repeat: ImageRepeat.repeat,
                                        opacity: _currentTheme == "Dark"
                                            ? 0.02
                                            : 0.05,
                                      ),
                                    ),
                                  ),
                                ),

                                // ✅ Big Watermark Logo
                                Center(
                                  child: Opacity(
                                    opacity: 0.15,
                                    child: Image.asset(
                                      "assets/images/bigilu_logo21.png",
                                      width: 280,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),

                                // Spine Shade (Curvature)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          Colors.black.withOpacity(
                                            _currentTheme == "Dark" ? 0.3 : 0.1,
                                          ),
                                          Colors.black.withOpacity(0.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Content Height Constraint
                                SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      _horizontalPadding,
                                      60,
                                      _horizontalPadding * 0.8,
                                      100,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          _alignment == TextAlign.center
                                          ? CrossAxisAlignment.center
                                          : (_alignment == TextAlign.justify
                                                ? CrossAxisAlignment.stretch
                                                : CrossAxisAlignment.start),
                                      children: [
                                        ...blocks.map<Widget>((block) {
                                          if (block['type'] == 'text') {
                                            bool isHeadline =
                                                block['isHeadline'] ?? false;
                                            return Padding(
                                              padding: EdgeInsets.only(
                                                bottom: isHeadline ? 32 : 24,
                                                top: isHeadline ? 12 : 0,
                                              ),
                                              child: SelectableText(
                                                block['text'] ?? "",
                                                textAlign: _alignment,
                                                style: TextStyle(
                                                  fontSize: isHeadline
                                                      ? _fontSize * 1.3
                                                      : _fontSize,
                                                  fontFamily: _fontFamily,
                                                  backgroundColor:
                                                      block['isHighlighted'] ==
                                                          true
                                                      ? const Color(
                                                          0xFFFFF1A1,
                                                        ).withOpacity(0.8)
                                                      : null,
                                                  color: textColor.withOpacity(
                                                    isHeadline ? 1.0 : 0.85,
                                                  ),
                                                  height: _lineHeight,
                                                  letterSpacing: _letterSpacing,
                                                  fontWeight: isHeadline
                                                      ? FontWeight.w900
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                            );
                                          }
                                          if (block['type'] == 'image') {
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 32,
                                                top: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.1),
                                                    blurRadius: 20,
                                                    offset: const Offset(0, 10),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(
                                                  fullImageUrl(block['image']),
                                                  fit: BoxFit.cover,
                                                  loadingBuilder:
                                                      (
                                                        context,
                                                        child,
                                                        progress,
                                                      ) {
                                                        if (progress == null) {
                                                          return child;
                                                        }
                                                        return Container(
                                                          height: 200,
                                                          color: textColor
                                                              .withOpacity(
                                                                0.03,
                                                              ),
                                                          child: const Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                          ),
                                                        );
                                                      },
                                                ),
                                              ),
                                            );
                                          }
                                          return const SizedBox();
                                        }).toList(),
                                      ],
                                    ),
                                  ),
                                ),

                                // Elegant Footer Page Number
                                Positioned(
                                  bottom: 25,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: brandColor.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        "—  ${index + 1}  —",
                                        style: TextStyle(
                                          color: brandColor.withOpacity(0.4),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                          fontFamily: 'serif',
                                          letterSpacing: 2.0,
                                        ),
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

          // Floating Interaction Bar (Bottom)
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: GestureDetector(
                    onTap: _showPagePicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _currentTheme == "Dark"
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: textColor.withOpacity(0.1),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            color: textColor.withOpacity(0.6),
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "${currentPage + 1} of ${widget.pages.length}",
                            style: TextStyle(
                              color: textColor.withOpacity(0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: textColor.withOpacity(0.4),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPage(Color paperColor, Color textColor) {
    List<String> summaryPoints = _generateSummaryPoints();

    return SizedBox.expand(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 75),
        decoration: BoxDecoration(
          color: paperColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                _currentTheme == "Dark" ? 0.5 : 0.2,
              ),
              blurRadius: 30,
              offset: const Offset(0, 15),
              spreadRadius: -8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Crystal Atmosphere Background
              Positioned.fill(
                child: Opacity(
                  opacity: 0.05,
                  child: Image.network(
                    "https://www.transparenttextures.com/patterns/crystal-white.png",
                    repeat: ImageRepeat.repeat,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              ),

              // ✅ Big Watermark Logo
              Center(
                child: Opacity(
                  opacity: 0.15,
                  child: Image.asset(
                    "assets/images/bigilu_logo21.png",
                    width: 280,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              Padding(
                padding: EdgeInsets.fromLTRB(
                  _horizontalPadding * 0.8,
                  80,
                  _horizontalPadding * 0.8,
                  40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Premium Summary Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "QUICK CONTEXT",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Headline
                    Text(
                      "Inside this story",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'serif',
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Generated Summary Points
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: summaryPoints.map((point) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFFFD700,
                                      ).withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: Color(0xFFDAA520),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      point,
                                      style: TextStyle(
                                        color: textColor.withOpacity(0.85),
                                        fontSize: 17,
                                        fontFamily: _fontFamily,
                                        height: 1.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Reader Invitation
                    Text(
                      "Tap or swipe to begin reading",
                      style: TextStyle(
                        color: textColor.withOpacity(0.4),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Progress Highlight
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 4,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _generateSummaryPoints() {
    List<String> textBlocks = [];

    for (var page in widget.pages.take(8)) {
      final blocks = page['blocks'] as List? ?? [];
      for (var block in blocks) {
        if (block['type'] == 'text' && block['text'] != null) {
          String text = block['text'].toString().trim();
          if (text.length > 30) {
            textBlocks.add(text);
          }
        }
      }
    }

    if (textBlocks.isEmpty) {
      return [
        "Discover the unique themes of this storyteller.",
        "Experience a deep dive into this narrative.",
        "Follow the journey through every page.",
      ];
    }

    String fullContent = textBlocks.join(" ");
    List<String> sentences = fullContent.split(RegExp(r'(?<=[.!?])\s+'));

    // Clean and take up to 3 points
    List<String> points = sentences
        .where((s) => s.length > 15)
        .take(3)
        .map((s) => s.trim())
        .toList();

    // Ensure we have at least 3 points
    if (points.length < 3) {
      points.add("A captivating journey written by ${widget.username}.");
    }

    return points;
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final sheetBg = _currentTheme == "Dark"
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFFDFBF7);
            final sheetText = _getTextColor();
            const brandColor = Color(0xFFB11226);

            return Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 40,
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: sheetText.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "DISPLAYS",
                        style: TextStyle(
                          color: sheetText.withOpacity(0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            _fontSize = 18.0;
                            _fontFamily = "Lora";
                            _lineHeight = 1.6;
                            _letterSpacing = 0.2;
                            _horizontalPadding = 50.0;
                            _currentTheme = "Sepia";
                            _alignment = TextAlign.left;
                          });
                          setState(() {});
                          _saveSettings();
                        },
                        child: Text(
                          "RESET",
                          style: TextStyle(
                            color: brandColor.withOpacity(0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Font Size Control
                  _buildControlSection(
                    label: "FONT SIZE",
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSettingsIconBtn(Icons.remove_rounded, () {
                          if (_fontSize > 12) {
                            setSheetState(() => _fontSize--);
                            setState(() {});
                            _saveSettings();
                          }
                        }, sheetText),
                        Text(
                          "${_fontSize.toInt()} px",
                          style: TextStyle(
                            color: sheetText,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'serif',
                          ),
                        ),
                        _buildSettingsIconBtn(Icons.add_rounded, () {
                          if (_fontSize < 36) {
                            setSheetState(() => _fontSize++);
                            setState(() {});
                            _saveSettings();
                          }
                        }, sheetText),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Theme Control
                  _buildControlSection(
                    label: "APPEARANCE",
                    child: Row(
                      children: ["Light", "Sepia", "Dark"].map<Widget>((t) {
                        final isSel = _currentTheme == t;
                        Color themeColor;
                        switch (t) {
                          case "Light":
                            themeColor = Colors.white;
                            break;
                          case "Sepia":
                            themeColor = const Color(0xFFFDFBF7);
                            break;
                          case "Dark":
                            themeColor = const Color(0xFF2C2C2C);
                            break;
                          default:
                            themeColor = Colors.white;
                        }
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setSheetState(() => _currentTheme = t);
                              setState(() {});
                              _saveSettings();
                            },
                            child: Column(
                              children: [
                                Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: themeColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSel
                                          ? brandColor
                                          : sheetText.withOpacity(0.1),
                                      width: isSel ? 2 : 1,
                                    ),
                                    boxShadow: isSel
                                        ? [
                                            BoxShadow(
                                              color: brandColor.withOpacity(
                                                0.15,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 6),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: isSel
                                      ? const Center(
                                          child: Icon(
                                            Icons.check_rounded,
                                            color: brandColor,
                                            size: 20,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t,
                                  style: TextStyle(
                                    color: isSel
                                        ? sheetText
                                        : sheetText.withOpacity(0.5),
                                    fontSize: 11,
                                    fontWeight: isSel
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildControlSection({required String label, required Widget child}) {
    final textColor = _getTextColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textColor.withOpacity(0.35),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildSettingsIconBtn(
    IconData icon,
    VoidCallback onTap,
    Color color, {
    double size = 46,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  void _showPagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final paperColor = _getPaperColor();
        final textColor = _getTextColor();
        const brandColor = Color(0xFFB11226);

        return Container(
          decoration: BoxDecoration(
            color: paperColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Table of Contents",
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'serif',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 340,
                child: GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: widget.pages.length,
                  itemBuilder: (context, index) {
                    final isCurrent = index == currentPage;
                    return GestureDetector(
                      onTap: () {
                        _controller.jumpToPage(index);
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? brandColor
                              : textColor.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? Colors.transparent
                                : textColor.withOpacity(0.08),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "${index + 1}",
                          style: TextStyle(
                            color: isCurrent
                                ? Colors.white
                                : textColor.withOpacity(0.8),
                            fontWeight: isCurrent
                                ? FontWeight.w900
                                : FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
