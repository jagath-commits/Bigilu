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
    } catch (_) {} finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset("assets/images/vijay1.jpg", fit: BoxFit.cover),
              ),
              Positioned.fill(child: Container(color: Colors.black.withOpacity(0.5))),
              Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(screenWidth * 0.04),
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: "Search hashtag...",
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.95),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setState(() => searchText = v),
                    ),
                  ),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : ListView(
                            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
                            children: hashtags
                                .where((i) => i["hashtag"]
                                    .toLowerCase()
                                    .contains(searchText.toLowerCase()))
                                .map((item) {
                              return GestureDetector(
                                onTap: () {
                                  final route = Platform.isIOS
                                      ? CupertinoPageRoute(
                                          builder: (_) => HashtagPostsPage(tag: item["hashtag"]),
                                        )
                                      : MaterialPageRoute(
                                          builder: (_) => HashtagPostsPage(tag: item["hashtag"]),
                                        );
                                  Navigator.push(context, route);
                                },
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: screenWidth * 0.02),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item["hashtag"],
                                          style: TextStyle(
                                              fontSize: screenWidth * 0.055,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white)),
                                      Text("${item["count"]} write up",
                                          style: TextStyle(
                                              fontSize: screenWidth * 0.04,
                                              color: Colors.grey[300])),
                                      const Divider(color: Colors.white30),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return BottomAppBar(
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
                  Platform.isIOS
                      ? CupertinoPageRoute(builder: (_) => ProfilePage(userId: userId))
                      : MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)),
                );
              }
            },
          ),
          const Icon(Icons.tag, color: Colors.white),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                Platform.isIOS
                    ? CupertinoPageRoute(builder: (_) => const HomePage())
                    : MaterialPageRoute(builder: (_) => const HomePage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                Platform.isIOS
                    ? CupertinoPageRoute(builder: (_) => const WritePage())
                    : MaterialPageRoute(builder: (_) => const WritePage()),
              );
            },
          ),
        ],
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
        setState(() {
          posts = data;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching hashtag posts: $e");
      setState(() => isLoading = false);
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

      if (response.statusCode == 200) {
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
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: const Color(0xFF800000),
        title: Text(widget.tag),
        centerTitle: Platform.isIOS, // iOS style
      ),

      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : posts.isEmpty
                ? const Center(child: Text("No posts found"))
                : ListView.builder(
                    physics: const BouncingScrollPhysics(), // iOS smooth scroll
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      final post = posts[index];
                      final postId = post['post_id'].toString();

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PostContainer(
                            post: post,
                            
                            isSaved: savedPosts.contains(postId),
                            
                            onSave: () => toggleSave(postId),
                          ),

                          if ((post['caption'] ?? "").toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  post['caption'],
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
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  post['hastag'],
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ),

                          const SizedBox(height: 8),
                          Divider(height: 1, thickness: 0.5),
                          const SizedBox(height: 6),
                        ],
                      );
                    },
                  ),
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
        Uri.parse(
          "https://bigiluu.com/api/posts/singlePost/${widget.postId}",
        ),
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
    final totalPages = pages.length;

    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
        title: const Text("Post"),
        centerTitle: Platform.isIOS, // iOS style title
      ),

      body: SafeArea(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.black),
              )
            : Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(), // iOS smooth scroll
                    itemCount: totalPages,
                    onPageChanged: (index) {
                      setState(() => currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      final page = pages[index];

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...(page['blocks'] as List).map<Widget>((block) {
                              if (block['type'] == "text") {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    block['text'] ?? "",
                                    style: TextStyle(
                                      fontSize:
                                          (page['fontSize'] ?? 16).toDouble(),
                                      color: _parseColor(page['fontColor']),
                                      fontFamily: page['fontFamily'],
                                    ),
                                  ),
                                );
                              }

                              if (block['type'] == "image" &&
                                  block['image'] != null &&
                                  block['image'].toString().isNotEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Image.network(
                                    "https://bigiluu.com/${block['image']}",
                                    fit: BoxFit.contain,
                                    loadingBuilder:
                                        (context, child, progress) {
                                      if (progress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                    errorBuilder:
                                        (context, error, stackTrace) {
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

                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${currentPage + 1} / $totalPages",
                        style: const TextStyle(
                          color: Colors.black,
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