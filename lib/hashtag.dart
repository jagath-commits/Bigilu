import 'dart:convert';
import 'dart:io' show Platform;
import 'package:bigilu/home.dart';
import 'package:bigilu/profile1.dart';
import 'package:bigilu/write.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class HashtagPage extends StatefulWidget {
  const HashtagPage({super.key});

  @override
  State<HashtagPage> createState() => _HashtagPageState();
}

class _HashtagPageState extends State<HashtagPage> {
  List<Map<String, dynamic>> hashtags = [];
  String searchText = "";
  bool isLoading = true;
  final TextEditingController _controller = TextEditingController();

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  @override
  void initState() {
    super.initState();
    fetchHashtags();
  }

  Future<void> fetchHashtags() async {
    try {
      final response = await http.get(
        Uri.parse("http://bigiluu.com/api/posts/hashtags"),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => hashtags = List<Map<String, dynamic>>.from(data));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          "Explore Hashtags",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        backgroundColor: brandColor,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: TextField(
                controller: _controller,
                onChanged: (v) => setState(() => searchText = v),
                style: const TextStyle(fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: "Search hashtags...",
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: const Icon(Icons.search, color: brandColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                ),
              ),
            ),
          ),

          // Hashtag List
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: brandColor),
                  )
                : ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    children: hashtags
                        .where(
                          (i) => i["hashtag"].toLowerCase().contains(
                            searchText.toLowerCase(),
                          ),
                        )
                        .map((item) {
                          return GestureDetector(
                            onTap: () {
                              final route = Platform.isIOS
                                  ? CupertinoPageRoute(
                                      builder: (_) => HashtagPostsPage(
                                        tag: item["hashtag"],
                                      ),
                                    )
                                  : MaterialPageRoute(
                                      builder: (_) => HashtagPostsPage(
                                        tag: item["hashtag"],
                                      ),
                                    );
                              Navigator.push(context, route);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.black.withOpacity(0.02),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: brandColor.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.tag_rounded,
                                      color: brandColor,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item["hashtag"],
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "${item["count"]} stories published",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Colors.grey.shade300,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

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
              _build3DNavItem(
                context,
                Icons.explore_rounded,
                "Explore",
                () {},
                isActive: true,
              ),
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

class HashtagPostsPage extends StatefulWidget {
  final String tag;

  const HashtagPostsPage({super.key, required this.tag});

  @override
  State<HashtagPostsPage> createState() => _HashtagPostsPageState();
}

class _HashtagPostsPageState extends State<HashtagPostsPage> {
  List posts = [];
  bool isLoading = true;

  Set<String> likedPosts = {};
  Set<String> savedPosts = {};

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  @override
  void initState() {
    super.initState();
    fetchPosts();
  }

  Future<void> fetchPosts() async {
    try {
      final cleanTag = widget.tag.replaceAll("#", "");
      final response = await http.get(
        Uri.parse("https://bigiluu.com/api/posts/hashtags/$cleanTag/posts"),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            posts = data;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching hashtag posts: $e");
      if (mounted) setState(() => isLoading = false);
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
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'post_id': postId}),
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          savedPosts.contains(postId)
              ? savedPosts.remove(postId)
              : savedPosts.add(postId);
        });
      }
    } catch (e) {
      debugPrint("Error saving post: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.tag,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: brandColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: brandColor))
          : posts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No stories found for ${widget.tag}",
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 20),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final postId = post['post_id'].toString();

                return PostContainer(
                  post: post,
                  isLiked: likedPosts.contains(postId),
                  onLike: () => toggleLike(postId),
                  isSaved: savedPosts.contains(postId),
                  onSave: () => toggleSave(postId),
                );
              },
            ),
    );
  }
}

class PostDetailPage extends StatefulWidget {
  final String postId;

  const PostDetailPage({super.key, required this.postId});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

List<dynamic> parsePages(String content) {
  return jsonDecode(content);
}

class _PostDetailPageState extends State<PostDetailPage> {
  List<dynamic> pages = [];
  String? coverImg;
  String? caption;
  bool loading = true;

  int currentPage = 0;
  final PageController _pageController = PageController(initialPage: 0);

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    try {
      final response = await http.get(
        Uri.parse("https://bigiluu.com/api/posts/singlePost/${widget.postId}"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        List<dynamic> parsedPages = [];

        if (data['content'] != null && data['content'].toString().isNotEmpty) {
          parsedPages = await compute(parsePages, data['content'].toString());
        }

        if (!mounted) return;

        setState(() {
          coverImg = data['cover_img'];
          caption = data['caption'];
          pages = parsedPages;
          loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => loading = false);
      }
    } catch (e) {
      debugPrint("Error loading post: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);
    final totalPages = pages.length;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              "Reading",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                fontFamily: 'serif',
              ),
            ),
            Text(
              "Page ${currentPage + 1} of $totalPages",
              style: TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: brandColor))
          : Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: totalPages,
                    onPageChanged: (index) {
                      setState(() => currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      final page = pages[index];
                      final fontSize = (page['fontSize'] ?? 18).toDouble();
                      final fontFamily = page['fontFamily'] ?? 'Roboto';
                      final fontColor = _parseColor(page['fontColor']);

                      return SizedBox.expand(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 75),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDFBF7),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 25,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 35,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          Colors.black.withOpacity(0.18),
                                          Colors.black.withOpacity(0.08),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
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
                                SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      55,
                                      50,
                                      40,
                                      70,
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
                                              padding: const EdgeInsets.only(
                                                bottom: 20,
                                              ),
                                              child: Text(
                                                block['text'] ?? "",
                                                style: TextStyle(
                                                  fontSize: fontSize,
                                                  fontFamily: fontFamily,
                                                  color: fontColor.withOpacity(
                                                    0.9,
                                                  ),
                                                  height: 1.7,
                                                  letterSpacing: 0.4,
                                                  fontWeight: FontWeight.w400,
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
                                              margin: const EdgeInsets.only(
                                                bottom: 24,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.12),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 5),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: Image.network(
                                                  "https://bigiluu.com/${block['image']}",
                                                  fit: BoxFit.cover,
                                                  loadingBuilder:
                                                      (
                                                        context,
                                                        child,
                                                        progress,
                                                      ) {
                                                        if (progress == null)
                                                          return child;
                                                        return Container(
                                                          height: 200,
                                                          color: Colors
                                                              .grey
                                                              .shade50,
                                                          child: const Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                  color:
                                                                      brandColor,
                                                                ),
                                                          ),
                                                        );
                                                      },
                                                ),
                                              ),
                                            );
                                          }
                                          return const SizedBox();
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 24,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Text(
                                      "— ${index + 1} of $totalPages —",
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
