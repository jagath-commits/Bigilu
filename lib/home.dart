import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:bigilu/PrivacyPage.dart';
import 'package:bigilu/TermsPage.dart';
import 'package:bigilu/hashtag.dart';
import 'package:bigilu/profile1.dart';
import 'package:bigilu/write.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';

class HomePage extends StatefulWidget {
  final String? deepLinkPostId;

  const HomePage({super.key, this.deepLinkPostId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  StreamSubscription? _linkSub;

  Set<String> likedPosts = {};
  Set<String> savedPosts = {};
  List posts = [];
  bool isLoading = true;

  Future<String?> getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  bool interactionsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadInteractionsLocal(); // 🔥 Load from cache immediately

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      initDeepLinks();
      await fetchPosts();
      if (widget.deepLinkPostId != null && !isDeepLinkHandled) {
        isDeepLinkHandled = true;
        openPostFromDeepLink(widget.deepLinkPostId!);
      }
    });
  }

  late AppLinks _appLinks;

  void initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      // 🔥 INITIAL LINK
      final uri = await _appLinks.getInitialLink();

      if (uri != null) {
        handleLink(uri.toString());
      }

      // 🔥 STREAM LISTENER
      _linkSub = _appLinks.uriLinkStream.listen((uri) {
        handleLink(uri.toString());
      });
    } catch (e) {
      print("Deep link error: $e");
    }
  }

  bool isDeepLinkHandled = false;

  void handleLink(String link) {
    print("🔥 Deep link: $link");

    Uri uri = Uri.parse(link);

    if (uri.pathSegments.isNotEmpty && uri.pathSegments.contains("post")) {
      if (isDeepLinkHandled) return; // ✅ move inside

      String postId = uri.pathSegments.last;

      isDeepLinkHandled = true; // ✅ set only when valid
      openPostFromDeepLink(postId);
    }
  }

  Future<void> fetchUserInteractions() async {
    if (interactionsLoaded) return; // 🔥 PREVENT DUPLICATE
    interactionsLoaded = true;
    String? userId = await getUserId();
    if (userId == null) return;

    print("🔄 Fetching user interactions for: $userId");

    // 1. Fetch Saved Posts
    try {
      final savedResponse = await http
          .get(Uri.parse("https://bigiluu.com/api/posts/savedPosts/$userId"))
          .timeout(const Duration(seconds: 10));

      if (savedResponse.statusCode == 200) {
        final data = jsonDecode(savedResponse.body);
        final List savedData = data['data'] ?? [];
        setState(() {
          savedPosts = savedData.map((e) => e['post_id'].toString()).toSet();
        });
        print("✅ Captured ${savedPosts.length} saved posts");
      }
    } catch (e) {
      print("⚠️ Error fetching saved posts: $e");
    }

    // 2. Fetch Supported (Liked) Posts
    try {
      // Assuming endpoint follows same pattern as savePost
      final likedResponse = await http
          .get(
            Uri.parse("https://bigiluu.com/api/posts/supportedPosts/$userId"),
          )
          .timeout(const Duration(seconds: 10));

      if (likedResponse.statusCode == 200) {
        final data = jsonDecode(likedResponse.body);
        final List likedData = data['data'] ?? [];
        setState(() {
          likedPosts = likedData.map((e) => e['post_id'].toString()).toSet();
        });
        print("✅ Captured ${likedPosts.length} supported posts");
        _saveInteractionsLocal(); // ✅ Update cache
      }
    } catch (e) {
      // If endpoint doesn't exist, we might need to check if getAllPosts returns it
      // or if there's another way. For now, we handle it gracefully.
      print("⚠️ Error fetching supported posts: $e");
    }
  }

  Future<void> _loadInteractionsLocal() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      likedPosts = (prefs.getStringList('cached_liked_posts') ?? []).toSet();
      savedPosts = (prefs.getStringList('cached_saved_posts') ?? []).toSet();
    });
    print(
      "📦 Loaded local cache: ${likedPosts.length} likes, ${savedPosts.length} saves",
    );
  }

  Future<void> _saveInteractionsLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('cached_liked_posts', likedPosts.toList());
    await prefs.setStringList('cached_saved_posts', savedPosts.toList());
  }

  /*@override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh posts when app comes to foreground
      fetchPosts();
    }
  }*/

  @override
  void dispose() {
    _linkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> openPostFromDeepLink(String postId) async {
    try {
      final response = await http
          .get(Uri.parse("https://bigiluu.com/api/posts/singlePost/$postId"))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print("⚠️ openPostFromDeepLink timeout");
              throw TimeoutException("Deep link request timed out");
            },
          );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final post = jsonData;

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

  bool isFetchingPosts = false;

  Future<void> fetchPosts() async {
    if (isFetchingPosts) return;

    isFetchingPosts = true;

    try {
      final response = await http
          .get(Uri.parse("https://bigiluu.com/api/posts/getAllPosts"))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print("❌ API TIMEOUT");
              throw TimeoutException("API timeout");
            },
          );

      print("🔥 API RESPONSE: ${response.body}"); // ✅ ADD THIS DEBUG

      if (response.statusCode == 200) {
        dynamic data;

        try {
          data = json.decode(response.body);
        } catch (e) {
          print("❌ JSON ERROR: $e");
          setState(() => isLoading = false);
          return;
        }

        setState(() {
          posts = data["data"] ?? [];
          isLoading = false; // ✅ IMPORTANT
        });

        fetchUserInteractions();
      } else {
        // 🔥 HANDLE ERROR STATUS
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print("❌ ERROR: $e");

      // 🔥 THIS IS THE MAIN FIX
      setState(() {
        isLoading = false;
      });
    } finally {
      isFetchingPosts = false;
    }
  }

  Future<void> toggleLike(String postId) async {
    final isAlreadyLiked = likedPosts.contains(postId);
    final String? userId = await getUserId();
    if (userId == null) return;

    // ✅ UI instant update
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

    // ✅ SINGLE API CALL
    try {
      final response = await http.post(
        Uri.parse("https://bigiluu.com/api/posts/toggleSupport"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "post_id": postId,
          "user_id": userId,
          "action": isAlreadyLiked ? "unlike" : "like",
        }),
      );

      final data = jsonDecode(response.body);

      setState(() {
        for (var p in posts) {
          if (p['post_id']?.toString() == postId) {
            p['support_count'] = data['support_count'];
            break;
          }
        }
      });
    } catch (e) {
      print("❌ Support API error: $e");
    }
  }

  void toggleSave(String postId) async {
    String? userId = await getUserId();
    if (userId == null) return;

    final bool isAlreadySaved = savedPosts.contains(postId);

    try {
      if (isAlreadySaved) {
        // 🔥 REMOVE / UNSAVE
        final url = Uri.parse(
          "https://bigiluu.com/api/posts/removeSavedPost/$userId/$postId",
        );
        final response = await http
            .delete(url)
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          setState(() {
            savedPosts.remove(postId);
          });
          _saveInteractionsLocal(); // ✅ Update local cache
          print("✅ Removed from saved");
        } else {
          print("❌ Failed to remove from saved: ${response.body}");
        }
      } else {
        // 🔥 SAVE
        final url = Uri.parse("https://bigiluu.com/api/posts/savePost");
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'user_id': userId, 'post_id': postId}),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          setState(() {
            savedPosts.add(postId);
          });
          _saveInteractionsLocal(); // ✅ Update local cache
          print("✅ Post saved successfully");
        } else {
          print("❌ Failed to save post: ${response.body}");
        }
      }
    } on TimeoutException {
      print("⚠️ Timeout toggling save");
    } catch (e) {
      print("Error toggling save: $e");
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
            : posts.isEmpty
            ? const Center(child: Text("No posts available"))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  final post = posts[index];
                  final String postId = post['post_id']?.toString() ?? "";

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
                        builder: (_) => ProfilePage(
                          userId: userId,
                          isPublicView: false, // 🔥 IMPORTANT
                        ),
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

class PostContainer extends StatefulWidget {
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

  @override
  State<PostContainer> createState() => _PostContainerState();
}

class _PostContainerState extends State<PostContainer> {
  bool _isOpeningPost = false;
  final GlobalKey _cardKey = GlobalKey();

  Future<void> _sharePostAsImage() async {
    try {
      // Small delay ensures frame is settled for capture
      await Future.delayed(const Duration(milliseconds: 50));

      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        // ignore: deprecated_member_use
        await Share.share(
          "Check out this story on Bigiluu! https://bigiluu.com/post/${widget.post['post_id']}",
        );
        return;
      }

      final ui.Image image = await boundary.toImage(
        pixelRatio: 2.5,
      ); // Slightly lower for stability
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final tempDir = Directory.systemTemp;
      final file = File(
        '${tempDir.path}/bigilu_card_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path, name: 'bigilu_story.png')],
        text:
            'Check out this story on Bigiluu! https://bigiluu.com/post/${widget.post['post_id']}',
      );
    } catch (e) {
      debugPrint("Error sharing post card image: $e");
      // ignore: deprecated_member_use
      await Share.share(
        "Check out this story on Bigiluu! https://bigiluu.com/post/${widget.post['post_id']}",
      );
    }
  }

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

  /*List<dynamic> list_pages() {
    final content = widget.post['content'];

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
  }*/

  String extractTitle() {
    return widget.post['title']?.toString() ?? "";
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);
    final caption = widget.post['caption']?.toString() ?? "";
    final hashtag = widget.post['hashtag']?.toString() ?? "";

    final screenWidth = MediaQuery.of(context).size.width;
    double paddingHorizontal = screenWidth < 360 ? 12 : 20;

    final String postIdStr = widget.post['post_id']?.toString() ?? "";

    // 🏆 Badge Variants Logic
    String ack = (widget.post['acknowledgment'] ?? "").toString().toUpperCase();

    String badgeLabel = "";
    List<Color> badgeGradients = [Colors.white, Colors.white];
    Color themeBorderColor = Colors.white;
    Color themeSpineColor = Colors.white.withOpacity(0.2);

    // 🔥 HANDLE EMPTY (WHITE)
    if (ack.isEmpty) {
      badgeLabel = ""; // no text OR you can put "NEW"
      badgeGradients = [Colors.white, Colors.white];
      themeBorderColor = Colors.white;
      themeSpineColor = Colors.white.withOpacity(0.1);
    }
    // 🥇 GOAT
    else if (ack == "GOAT") {
      badgeLabel = "GOAT";
      badgeGradients = [const Color(0xFFFFD700), const Color(0xFFDAA520)];
      themeBorderColor = const Color(0xFFFFD700);
      themeSpineColor = const Color(0xFFFFD700).withOpacity(0.2);
    }
    // 🥈 MERSAL
    else if (ack == "MERSAL") {
      badgeLabel = "MERSAL";
      badgeGradients = [const Color(0xFFE0E0E0), const Color(0xFF9E9E9E)];
      themeBorderColor = const Color(0xFFC0C0C0);
      themeSpineColor = const Color(0xFFE0E0E0).withOpacity(0.25);
    }
    // 🥉 THERI
    else if (ack == "THERI") {
      badgeLabel = "THERI";
      badgeGradients = [const Color(0xFFCD7F32), const Color(0xFF8B4513)];
      themeBorderColor = const Color(0xFFCD7F32);
      themeSpineColor = const Color(0xFFCD7F32).withOpacity(0.2);
    }
    return GestureDetector(
      onTap: () async {
        if (_isOpeningPost) return; // ✅ Block multiple clicks
        setState(() => _isOpeningPost = true);

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

            if (!context.mounted) {
              if (mounted) setState(() => _isOpeningPost = false);
              return;
            }

            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenPostViewer(
                  pages: pages,
                  username: widget.post['username']?.toString() ?? "",
                  profileImage: widget.post['profile_image']?.toString() ?? "",
                  postId: postIdStr,
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint("Error loading single post: $e");
        } finally {
          if (mounted) {
            setState(() => _isOpeningPost = false);
          }
        }
      },
      child: RepaintBoundary(
        key: _cardKey,
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
                child: GestureDetector(
                  onTap: () {
                    final userId = widget.post['user_id']?.toString();

                    if (userId != null && userId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfilePage(
                            userId: userId,
                            isPublicView: true, // 🔥 ADD THIS
                          ),
                        ),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFB11226).withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey.shade100,
                          backgroundImage: NetworkImage(
                            fullUrl(widget.post['profile_image'] ?? ''),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.post['username'] ?? "Bigiluu Member",
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB11226).withOpacity(0.08),
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
                              "${widget.post['readers_count'] ?? 0}",
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
              ),

              // Hyper-Realistic 3D Book Cover
              Padding(
                padding: EdgeInsets.symmetric(horizontal: paddingHorizontal),
                child: Hero(
                  tag: "post_${widget.post['post_id']}",
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
                                  Builder(
                                    builder: (context) {
                                      final coverUrl = fullUrl(
                                        widget.post['cover_img'],
                                      );
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
                                        loadingBuilder:
                                            (context, child, progress) {
                                              if (progress == null)
                                                return child;
                                              return Container(
                                                color: const Color(0xFFF8F8F8),
                                                child: const Center(
                                                  child:
                                                      CircularProgressIndicator(
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
                                    },
                                  ),

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

                                  // 📖 Book Title — matching Cover Design exactly
                                  if ((widget.post['title']?.toString() ?? '')
                                      .isNotEmpty)
                                    Positioned(
                                      top: 15,
                                      left: 10,
                                      right: 10,
                                      child: Builder(
                                        builder: (context) {
                                          // Parse title style from top-level and content JSON
                                          double fs = 15.0;
                                          String? ff;
                                          Color tc = Colors.white;
                                          try {
                                            double? parsedFs;
                                            Color? parsedTc;
                                            String? parsedFf;

                                            // 1. Try top-level post fields (stored by API)
                                            if (widget.post['titleFontSize'] !=
                                                    null &&
                                                widget.post['titleFontSize']
                                                    .toString()
                                                    .isNotEmpty) {
                                              parsedFs = double.tryParse(
                                                widget.post['titleFontSize']
                                                    .toString(),
                                              );
                                            }
                                            if (widget.post['titleColor'] !=
                                                    null &&
                                                widget.post['titleColor']
                                                    .toString()
                                                    .isNotEmpty) {
                                              int? cv = int.tryParse(
                                                widget.post['titleColor']
                                                    .toString(),
                                              );
                                              if (cv != null)
                                                parsedTc = Color(cv);
                                            }
                                            if (widget.post['titleFontFamily'] !=
                                                    null &&
                                                widget.post['titleFontFamily']
                                                    .toString()
                                                    .isNotEmpty) {
                                              parsedFf = widget
                                                  .post['titleFontFamily']
                                                  .toString();
                                            }

                                            // 2. Fallback to Content JSON
                                            dynamic raw =
                                                widget.post['content'];
                                            if (raw != null) {
                                              dynamic dec = raw;
                                              if (dec is String) {
                                                try {
                                                  dec = jsonDecode(dec);
                                                } catch (_) {}
                                              }
                                              if (dec is String) {
                                                try {
                                                  dec = jsonDecode(dec);
                                                } catch (_) {}
                                              }

                                              if (dec is Map) {
                                                if (parsedFs == null &&
                                                    dec['titleFontSize'] !=
                                                        null) {
                                                  parsedFs = double.tryParse(
                                                    dec['titleFontSize']
                                                        .toString(),
                                                  );
                                                }
                                                if (parsedTc == null &&
                                                    dec['titleColor'] != null) {
                                                  int? cv = int.tryParse(
                                                    dec['titleColor']
                                                        .toString(),
                                                  );
                                                  if (cv != null)
                                                    parsedTc = Color(cv);
                                                }
                                                if (parsedFf == null &&
                                                    dec['titleFontFamily'] !=
                                                        null) {
                                                  parsedFf =
                                                      dec['titleFontFamily']
                                                          .toString();
                                                }
                                              }
                                            }

                                            if (parsedFs != null)
                                              fs = (parsedFs * 0.6).clamp(
                                                12.0,
                                                45.0,
                                              );
                                            if (parsedTc != null) tc = parsedTc;
                                            if (parsedFf != null &&
                                                parsedFf.isNotEmpty)
                                              ff = parsedFf;
                                          } catch (_) {}
                                          return Text(
                                            widget.post['title']?.toString() ??
                                                '',
                                            textAlign: TextAlign.center,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: tc,
                                              fontSize: fs,
                                              fontFamily: ff,
                                              fontWeight: FontWeight.bold,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black
                                                      .withOpacity(0.6),
                                                  blurRadius: 10,
                                                  offset: const Offset(1, 1),
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildActionButton(
                      icon: Icons.touch_app_rounded,
                      topLabel: (widget.post['support_count'] ?? 0).toString(),
                      label: "Support",
                      color: widget.isLiked ? brandColor : null,
                      onTap: widget.onLike,
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.share_rounded,
                      label: "Share",
                      onTap: () => _sharePostAsImage(),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: widget.isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      label: widget.isSaved ? "Saved" : "Save",
                      color: widget.isSaved ? brandColor : null,
                      onTap: widget.onSave,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                      size: 18,
                      color: color ?? const Color(0xFF6E6E73),
                    ),
                    const SizedBox(width: 6),
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
        ],
      ),
    );
  }
}

class _ExpandableImage extends StatelessWidget {
  final String imageUrl;
  final Color textColor;
  const _ExpandableImage({required this.imageUrl, required this.textColor});

  void _showFullImage(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "FullImage",
      barrierColor: Colors.black.withOpacity(0.9),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  maxScale: 5.0,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => _showFullImage(context),
        child: Container(
          margin: const EdgeInsets.symmetric(
            vertical: 24,
          ), // Increased margin for better spacing
          width: double.infinity,
          height: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: imageUrl.isEmpty
                ? Container(
                    color: textColor.withOpacity(0.05),
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: textColor.withOpacity(0.05),
                        child: const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: textColor.withOpacity(0.03),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
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

  final GlobalKey _summaryKey = GlobalKey();
  late List<GlobalKey> _pageKeys;

  Future<void> _shareAsImage() async {
    try {
      RenderRepaintBoundary? boundary;

      // Try current page key if we're not on summary index
      if (currentPage == 0) {
        boundary =
            _summaryKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
      } else if (currentPage <= _pageKeys.length) {
        boundary =
            _pageKeys[currentPage - 1].currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
      }

      // Fallback
      if (boundary == null) {
        boundary =
            _summaryKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
      }

      if (boundary == null) {
        // Fallback to simple text/link share if capture fails
        // ignore: deprecated_member_use
        await Share.share(
          "Read this interesting story on Bigiluu! https://bigiluu.com/post/${widget.postId}",
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
        '${tempDir.path}/bigilu_share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'Read this interesting story on Bigiluu! https://bigiluu.com/post/${widget.postId}',
      );
    } catch (e) {
      debugPrint("Error sharing image: $e");
      // ignore: deprecated_member_use
      await Share.share(
        "Read this interesting story on Bigiluu! https://bigiluu.com/post/${widget.postId}",
      );
    }
  }

  // Reader Settings (Synced with uploaded UI & Writer Defaults)
  double _fontSize = 22.0;
  String _fontFamily = "Roboto";
  double _lineHeight = 1.4;
  TextAlign _alignment = TextAlign.left;
  double _letterSpacing = 0.0;
  double _horizontalPadding = 50.0;
  String _currentTheme = "Sepia"; // Light, Sepia, Dark

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _pageKeys = List.generate(widget.pages.length, (index) => GlobalKey());
    _loadSettings();
    loadLastPage();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble("reader_font_size") ?? 22.0;
      _fontFamily = prefs.getString("reader_font_family") ?? "Roboto";
      _lineHeight = prefs.getDouble("reader_line_height") ?? 1.4;
      _letterSpacing = prefs.getDouble("reader_letter_spacing") ?? 0.0;
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
            Uri.parse(
              "https://bigiluu.com/api/posts/singlePost/${widget.postId}",
            ),
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
        final updatedPost = jsonData;
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
                onPressed: () => _shareAsImage(),
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
                        child: RepaintBoundary(
                          key: (index > 0 && index - 1 < _pageKeys.length)
                              ? _pageKeys[index - 1]
                              : null,
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
                                              _currentTheme == "Dark"
                                                  ? 0.3
                                                  : 0.1,
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
                                    child: Builder(
                                      builder: (context) {
                                        final pageAlignIdx =
                                            (page['textAlign'] is num)
                                            ? (page['textAlign'] as num).toInt()
                                            : (int.tryParse(
                                                page['textAlign']?.toString() ??
                                                    "",
                                              ));
                                        final TextAlign pageAlignment =
                                            (pageAlignIdx != null &&
                                                pageAlignIdx >= 0 &&
                                                pageAlignIdx <
                                                    TextAlign.values.length)
                                            ? TextAlign.values[pageAlignIdx]
                                            : _alignment;

                                        final CrossAxisAlignment
                                        pageCrossAlign =
                                            pageAlignment == TextAlign.center
                                            ? CrossAxisAlignment.center
                                            : (pageAlignment ==
                                                      TextAlign.justify
                                                  ? CrossAxisAlignment.stretch
                                                  : CrossAxisAlignment.start);

                                        final double pageMargin =
                                            (page['pageMargin'] is num)
                                            ? (page['pageMargin'] as num)
                                                  .toDouble()
                                            : _horizontalPadding;

                                        final double pageFontSize = _fontSize;

                                        final double pageLineHeight =
                                            (page['lineSpacing'] is num)
                                            ? (page['lineSpacing'] as num)
                                                  .toDouble()
                                            : _lineHeight;

                                        final String pageFontFamily =
                                            page['fontFamily']?.toString() ??
                                            _fontFamily;
                                        final double pageLetterSpacing =
                                            (page['letterSpacing'] is num)
                                            ? (page['letterSpacing'] as num)
                                                  .toDouble()
                                            : _letterSpacing;

                                        return Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            pageMargin,
                                            40,
                                            pageMargin,
                                            40,
                                          ),
                                          child: Column(
                                            crossAxisAlignment: pageCrossAlign,
                                            children: [
                                              ...blocks.map<Widget>((block) {
                                                if (block['type'] == 'text') {
                                                  bool isHeadline =
                                                      block['isHeadline'] ??
                                                      false;
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 4,
                                                        ),
                                                    child: SelectableText(
                                                      isHeadline
                                                          ? (block['text'] ??
                                                                    "")
                                                                .toString()
                                                                .toUpperCase()
                                                          : (block['text'] ??
                                                                ""),
                                                      textAlign:
                                                          block['textAlign'] !=
                                                              null
                                                          ? TextAlign
                                                                .values[(block['textAlign']
                                                                    as num)
                                                                .toInt()]
                                                          : pageAlignment,
                                                      style: GoogleFonts.getFont(
                                                        block['fontFamily']
                                                                ?.toString() ??
                                                            pageFontFamily,
                                                        fontSize: isHeadline
                                                            ? pageFontSize * 1.3
                                                            : pageFontSize,
                                                        backgroundColor: null,
                                                        color:
                                                            block['fontColor'] !=
                                                                null
                                                            ? Color(
                                                                (block['fontColor']
                                                                        as num)
                                                                    .toInt(),
                                                              )
                                                            : textColor
                                                                  .withOpacity(
                                                                    isHeadline
                                                                        ? 1.0
                                                                        : 0.85,
                                                                  ),
                                                        height:
                                                            block['lineSpacing']
                                                                is num
                                                            ? (block['lineSpacing']
                                                                      as num)
                                                                  .toDouble()
                                                            : pageLineHeight,
                                                        letterSpacing:
                                                            isHeadline
                                                            ? -0.5
                                                            : (block['letterSpacing']
                                                                      is num
                                                                  ? (block['letterSpacing']
                                                                            as num)
                                                                        .toDouble()
                                                                  : pageLetterSpacing),
                                                        fontWeight: isHeadline
                                                            ? FontWeight.w900
                                                            : FontWeight.w400,
                                                      ),
                                                    ),
                                                  );
                                                }
                                                if (block['type'] == 'image') {
                                                  return _ExpandableImage(
                                                    imageUrl: fullImageUrl(
                                                      block['image'],
                                                    ),
                                                    textColor: textColor,
                                                  );
                                                }
                                                return const SizedBox();
                                              }).toList(),
                                            ],
                                          ),
                                        );
                                      },
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
                            "${currentPage + 1} of ${widget.pages.length + 1}",
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
    String summaryParagraph = _generateStorySummary();

    return SizedBox.expand(
      child: RepaintBoundary(
        key: _summaryKey,
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
                    50, // REDUCED VERTICAL PADDING FURTHER FURTHER
                    _horizontalPadding * 0.8,
                    30,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
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
                      const SizedBox(height: 12),

                      // Generated Summary (AI Analyzer - Perfect Paragraph)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: textColor.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: textColor.withOpacity(0.06),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    color: const Color(
                                      0xFFFFD700,
                                    ).withOpacity(0.8),
                                    size: 20,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    summaryParagraph,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.9),
                                      fontSize: 14.5,
                                      fontFamily: _fontFamily,
                                      height: 1.6,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

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
      ),
    );
  }

  String _generateStorySummary() {
    List<String> textBlocks = [];
    int imageCount = 0;

    for (var page in widget.pages) {
      final blocks = page['blocks'] as List? ?? [];
      for (var block in blocks) {
        if (block['type'] == 'text' && block['text'] != null) {
          String text = block['text'].toString().trim();
          if (text.length > 20) textBlocks.add(text);
        } else if (block['type'] == 'image') {
          imageCount++;
        }
      }
    }

    bool isTamil =
        textBlocks.isNotEmpty &&
        textBlocks.any((t) => t.contains(RegExp(r'[\u0B80-\u0BFF]')));

    if (textBlocks.isEmpty) {
      if (imageCount > 0) {
        if (isTamil) {
          return "இந்தத் தொகுப்பு $imageCount அற்புதமான படங்கள் மூலம் காட்சிப்படுத்தப்பட்டுள்ளது. இது ஒரு உணர்ச்சிகரமான காட்சிப் பயணத்தைத் தொடங்கி, இறுதியில் ஒரு அழகான காட்சி அனுபவமாக முடிகிறது.";
        }
        return "This visual narrative unfolds through a compelling sequence of $imageCount evocative images, beginning a silent journey that reaches a profound and artistic conclusion on the final page.";
      }
      return isTamil
          ? "வாசகர்களை ஈர்க்கும் ஒரு புதிய மற்றும் தனித்துவமான படைப்புத் தொகுப்பு."
          : "Explore a unique story collection and experience the storyteller's vivid vision through this narrative.";
    }

    String fullContent = textBlocks.join(" ").trim();
    List<String> sentences = fullContent.split(RegExp(r'(?<=[.!?])\s+'));
    List<String> meaningfulSentences = sentences
        .where((s) => s.length > 35)
        .toList();
    if (meaningfulSentences.isEmpty) meaningfulSentences = [textBlocks.first];

    List<String> selected = [];
    const int sampleCount = 5;
    if (meaningfulSentences.length <= sampleCount) {
      selected = meaningfulSentences;
    } else {
      for (int i = 0; i < sampleCount; i++) {
        int index = (i * (meaningfulSentences.length - 1) / (sampleCount - 1))
            .round();
        selected.add(meaningfulSentences[index]);
      }
    }

    List<String> cleanedSamples = selected.map((s) {
      String clean = s.trim().replaceAll(
        RegExp(
          r'^["'
          "'"
          r'\s]+|["'
          "'"
          r'\s]+$',
        ),
        "",
      );
      return clean.replaceAll(RegExp(r'\.+$'), "");
    }).toList();

    String summary = "";
    if (cleanedSamples.isNotEmpty) {
      if (isTamil) {
        summary =
            "இந்த படைப்பு ${cleanedSamples.first} என்ற கருப்பொருளில் தொடங்கி, கதையின் ஊடாக ${cleanedSamples[cleanedSamples.length ~/ 2]} போன்ற முக்கிய நகர்வுகளுடன் பயணித்து, இறுதியில் ${cleanedSamples.last} என ஒரு சிறப்பான முடிவை அடைகிறது. இது ஒரு முழுமையான வாசிப்பு அனுபவத்தை வழங்கும்.";
      } else {
        summary =
            "This work unfolds with the theme of ${cleanedSamples.first}. As the narrative progresses through ${cleanedSamples[cleanedSamples.length ~/ 2]}, it reaches its artistic pinnacle and concludes with ${cleanedSamples.last}.";
      }
    }

    summary = summary.replaceAll("..", ".").trim();
    if (summary.isNotEmpty && !summary.endsWith(".")) summary += ".";
    return summary.isEmpty ? "A story of passion and vision." : summary;
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
                  itemCount: widget.pages.length + 1,
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
