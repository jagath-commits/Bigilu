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
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:bigilu/cover_preview.dart';
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

  String _selectedCategory = "All";

  String _getPostCategory(dynamic post) {
    if (post['category'] != null && post['category'].toString().isNotEmpty) {
      return post['category'].toString();
    }
    final content = post['content'];
    if (content == null) {
      final coverImg =
          post['cover_img']?.toString() ?? post['coverUrl']?.toString() ?? '';
      final title = post['title']?.toString().trim() ?? '';
      if (coverImg.isEmpty && title.isEmpty) return "Manu";
      return "All";
    }

    dynamic decoded;
    try {
      if (content is String) {
        final trimmed = content.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          decoded = jsonDecode(trimmed);
        }
      } else {
        decoded = content;
      }
    } catch (_) {}

    if (decoded is Map && decoded['category'] != null)
      return decoded['category'].toString();
    if (decoded is Map &&
        decoded['pages'] is List &&
        decoded['pages'].isNotEmpty) {
      if (decoded['pages'][0] is Map &&
          decoded['pages'][0]['category'] != null) {
        return decoded['pages'][0]['category'].toString();
      }
    }
    if (decoded is List && decoded.isNotEmpty) {
      if (decoded[0] is Map && decoded[0]['category'] != null) {
        return decoded[0]['category'].toString();
      }
    }

    final coverImg =
        post['cover_img']?.toString() ?? post['coverUrl']?.toString() ?? '';
    final title = post['title']?.toString().trim() ?? '';
    if (coverImg.isEmpty && title.isEmpty) return "Manu";

    return "All";
  }

  List get _filteredPosts {
    if (_selectedCategory == "All") return posts;
    return posts
        .where((post) => _getPostCategory(post) == _selectedCategory)
        .toList();
  }

  Widget _buildModernTab(String id, String title) {
    final bool isSelected = _selectedCategory == id;
    const brandColor = Color(0xFFB11226);
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? brandColor : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? brandColor : Colors.grey.shade300,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: brandColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  bool isLoadingMore = false;
  int currentPage = 1;
  bool hasMore = true;
  final ScrollController _scrollController = ScrollController();

  Future<String?> getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  bool interactionsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadInteractionsLocal(); // ≡ƒöÑ Load from cache immediately

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scrollController.addListener(_onScroll);
      initDeepLinks();

      // Γ£à ONLY ONE CALL (PARALLEL)
      await loadCachedPosts(); // ≡ƒöÑ ADD THIS FIRST

      await Future.wait([
        fetchPosts(), // API refresh
        fetchUserInteractions(),
      ]);

      if (widget.deepLinkPostId != null && !isDeepLinkHandled) {
        isDeepLinkHandled = true;
        openPostFromDeepLink(widget.deepLinkPostId!);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final threshold = 300; // ≡ƒöÑ increase buffer

    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - threshold &&
        !isLoadingMore &&
        hasMore &&
        !isLoading &&
        !isFetchingPosts) {
      print("≡ƒöÑ LOAD MORE TRIGGERED - PAGE: $currentPage");

      fetchPosts(loadMore: true);
    }
  }

  late AppLinks _appLinks;

  void initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      // ≡ƒöÑ INITIAL LINK
      final uri = await _appLinks.getInitialLink();

      if (uri != null) {
        handleLink(uri.toString());
      }

      // ≡ƒöÑ STREAM LISTENER
      _linkSub = _appLinks.uriLinkStream.listen((uri) {
        if (uri != null) {
          handleLink(uri.toString());
        }
      });
    } catch (e) {
      print("Deep link error: $e");
    }
  }

  bool isDeepLinkHandled = false;

  void handleLink(String link) {
    print("≡ƒöÑ Deep link: $link");

    Uri uri = Uri.parse(link);

    if (uri.pathSegments.isNotEmpty && uri.pathSegments.contains("post")) {
      if (isDeepLinkHandled) return; // Γ£à move inside

      String postId = uri.pathSegments.last;

      isDeepLinkHandled = true; // Γ£à set only when valid
      openPostFromDeepLink(postId);
    }
  }

  Future<void> loadCachedPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_posts');

    if (cached != null) {
      final List decoded = jsonDecode(cached);

      setState(() {
        posts = decoded;
        isLoading = false;
      });

      print("ΓÜí Loaded cached posts: ${posts.length}");
    }
  }

  Future<void> fetchUserInteractions() async {
    if (interactionsLoaded) return; // ≡ƒöÑ PREVENT DUPLICATE
    interactionsLoaded = true;
    String? userId = await getUserId();
    if (userId == null) return;

    print("≡ƒöä Fetching user interactions for: $userId");

    // 1. Fetch Saved Posts
    try {
      final savedResponse = await http
          .get(Uri.parse("https://bigiluu.com/api/posts/savedPosts/$userId"))
          .timeout(const Duration(seconds: 30));

      if (savedResponse.statusCode == 200) {
        final data = jsonDecode(savedResponse.body);
        final List savedData = data['data'] ?? [];
        if (!mounted) return;
        setState(() {
          savedPosts = savedData.map((e) => e['post_id'].toString()).toSet();
        });
        print("Γ£à Captured ${savedPosts.length} saved posts");
      }
    } catch (e) {
      print("ΓÜá∩╕Å Error fetching saved posts: $e");
    }

    // 2. Fetch Supported (Liked) Posts
    try {
      // Assuming endpoint follows same pattern as savePost
      final likedResponse = await http
          .get(
            Uri.parse("https://bigiluu.com/api/posts/supportedPosts/$userId"),
          )
          .timeout(const Duration(seconds: 30));

      if (likedResponse.statusCode == 200) {
        final data = jsonDecode(likedResponse.body);
        final List likedData = data['data'] ?? [];
        if (!mounted) return;
        setState(() {
          likedPosts = likedData.map((e) => e['post_id'].toString()).toSet();
        });
        print("Γ£à Captured ${likedPosts.length} supported posts");
        _saveInteractionsLocal(); // Γ£à Update cache
      }
    } catch (e) {
      // If endpoint doesn't exist, we might need to check if getAllPosts returns it
      // or if there's another way. For now, we handle it gracefully.
      print("ΓÜá∩╕Å Error fetching supported posts: $e");
    }
  }

  Future<void> _loadInteractionsLocal() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      likedPosts = (prefs.getStringList('cached_liked_posts') ?? []).toSet();
      savedPosts = (prefs.getStringList('cached_saved_posts') ?? []).toSet();
    });
    print(
      "≡ƒôª Loaded local cache: ${likedPosts.length} likes, ${savedPosts.length} saves",
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> openPostFromDeepLink(String postId) async {
    try {
      final response = await http
          .get(Uri.parse("https://bigiluu.com/api/posts/getPost/$postId"))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print("ΓÜá∩╕Å openPostFromDeepLink timeout");
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
              postId: post['post_id'], // Γ£à ADD
            ),
          ),
        );
      }
    } on TimeoutException catch (e) {
      print("ΓÜá∩╕Å Deep link timeout: $e");
    } catch (e) {
      print("Deep link open error: $e");
    }
  }

  List<dynamic> extractPages(dynamic content) {
    try {
      // Γ£à IMPORTANT ADD
      if (content is List) return content;

      if (content is Map && content.containsKey("pages")) {
        return content["pages"] ?? [];
      }

      if (content is String) {
        final trimmed = content.trim();

        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          final decoded = jsonDecode(trimmed);

          if (decoded is List) return decoded;
          if (decoded is Map && decoded.containsKey("pages")) {
            return decoded["pages"] ?? [];
          }
        }
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  bool isFetchingPosts = false;

  Future<void> fetchPosts({bool loadMore = false}) async {
    if (isFetchingPosts) return;

    if (loadMore) {
      if (!hasMore) return;
      setState(() {
        isLoadingMore = true;
      });
    } else {
      setState(() {
        isLoading = true;
        currentPage = 1;
        hasMore = true;
      });
    }

    isFetchingPosts = true;

    try {
      final response = await http
          .get(
            Uri.parse(
              "https://bigiluu.com/api/posts/getAllPosts?page=$currentPage&limit=10",
            ),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List newPosts = data["data"] ?? [];

        if (!mounted) return;
        setState(() {
          if (loadMore) {
            final existingIds = posts
                .map((p) => p['post_id']?.toString())
                .toSet();
            final filteredNewPosts = newPosts
                .where((p) => !existingIds.contains(p['post_id']?.toString()))
                .toList();
            posts.addAll(filteredNewPosts);
          } else {
            posts = newPosts;
          }

          isLoading = false;
          isLoadingMore = false;

          if (newPosts.length < 10) {
            hasMore = false; // last page
          }

          if (newPosts.isNotEmpty) {
            currentPage++;
          }
        });

        _savePostsToCache(); // ≡ƒöÑ ADD HERE
        // Γ£à CALL ONLY AFTER POSTS LOAD
        if (!loadMore) {
          await Future.delayed(Duration(milliseconds: 300));
          if (!mounted) return;
        }
      } else {
        if (!mounted) return;
        setState(() {
          isLoading = false;
          isLoadingMore = false;
        });
      }
    } catch (e) {
      print("Γ¥î ERROR: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
        isLoadingMore = false;
      });
    } finally {
      isFetchingPosts = false;
    }
    print("≡ƒôä FETCHING PAGE: $currentPage, loadMore: $loadMore");
  }

  Future<void> _savePostsToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_posts', jsonEncode(posts));
    print("≡ƒÆ╛ Cached posts saved: ${posts.length}");
  }

  Future<void> toggleLike(String postId) async {
    final isAlreadyLiked = likedPosts.contains(postId);
    final String? userId = await getUserId();
    if (userId == null) return;

    // Γ£à UI instant update
    if (!mounted) return;
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

    // Γ£à SINGLE API CALL
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

      if (!mounted) return;
      setState(() {
        for (var p in posts) {
          if (p['post_id']?.toString() == postId) {
            p['support_count'] = data['support_count'];
            break;
          }
        }
      });
    } catch (e) {
      print("Γ¥î Support API error: $e");
    }
  }

  void toggleSave(String postId) async {
    print("≡ƒöÑ SAVE CLICKED: $postId"); // ADD THIS

    String? userId = await getUserId();
    print("≡ƒæñ USER ID: $userId"); // ADD THIS
    if (userId == null) return;

    final bool isAlreadySaved = savedPosts.contains(postId);

    try {
      if (isAlreadySaved) {
        // ≡ƒöÑ REMOVE / UNSAVE
        final url = Uri.parse(
          "https://bigiluu.com/api/posts/removeSavedPost/$userId/$postId",
        );
        final response = await http
            .delete(url)
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          setState(() {
            savedPosts.remove(postId);

            // ≡ƒöÑ FORCE UI UPDATE INSIDE POSTS
            for (var p in posts) {
              if (p['post_id'].toString() == postId) {
                p['is_saved'] = !isAlreadySaved;
              }
            }
          });
        } else {
          print("Γ¥î Failed to remove from saved: ${response.body}");
        }
      } else {
        // ≡ƒöÑ SAVE
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

            // ≡ƒöÑ FORCE UI UPDATE INSIDE POSTS
            for (var p in posts) {
              if (p['post_id'].toString() == postId) {
                p['is_saved'] = !isAlreadySaved;
              }
            }
          });
        } else {
          print("Γ¥î Failed to save post: ${response.body}");
        }
      }
    } on TimeoutException {
      print("ΓÜá∩╕Å Timeout toggling save");
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
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                itemCount: _filteredPosts.length + 1 + (isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        clipBehavior: Clip.none,
                        children: [
                          _buildModernTab("All", "α«àα«⌐α»êα«ñα»ìα«ñα»üα««α»ì"),
                          _buildModernTab("Manu", "α««α«⌐α»ü"),
                          _buildModernTab("Sinthanaigal", "α«Üα«┐α«¿α»ìα«ñα«⌐α»êα«òα«│α»ì"),
                          _buildModernTab("Budget", "α«¬α«ƒα»ìα«£α»åα«ƒα»ì"),
                          _buildModernTab("Poll", "α«╡α«╛α«òα»ìα«òα»åα«ƒα»üα«¬α»ìα«¬α»ü"),
                        ],
                      ),
                    );
                  }

                  final listIndex = index - 1;

                  if (listIndex == _filteredPosts.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFB11226),
                        ),
                      ),
                    );
                  }

                  final post = _filteredPosts[listIndex];
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
              _build3DNavItem(context, Icons.edit_rounded, "Write", () async {
                final category = await showCategorySelectionBottomSheet(
                  context,
                );
                if (category != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WritePage(category: category),
                    ),
                  );
                }
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
                          isPublicView: false, // ≡ƒöÑ IMPORTANT
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
  bool _isOpeningPost = false; // Γ£à Guard against double-tap

  Future<void> _sharePostWithImage() async {
    final String postIdStr = widget.post['post_id']?.toString() ?? "";
    final String title =
        widget.post['title']?.toString() ?? "Check out this story!";
    final String coverUrlStr = fullUrl(widget.post['cover_img']);
    final String shareLink = "https://bigiluu.com/post/$postIdStr";

    try {
      if (coverUrlStr.isEmpty) {
        await Share.share(shareLink, subject: title);
        return;
      }

      final response = await http.get(Uri.parse(coverUrlStr));
      if (response.statusCode == 200) {
        final tempDir = Directory.systemTemp;
        final file = File(
          '${tempDir.path}/post_share_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(response.bodyBytes);

        await Share.shareXFiles([
          XFile(file.path),
        ], text: '$title\n\n$shareLink');
      } else {
        await Share.share(shareLink, subject: title);
      }
    } catch (e) {
      debugPrint("Error sharing post: $e");
      await Share.share(shareLink, subject: title);
    }
  }

  String fullUrl(String? path) {
    if (path == null || path.isEmpty) {
      return "";
    }

    // Γ£à If already a complete URL (http or https), return as-is but ensure HTTPS
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

    // Γ£à Clean up path
    path = path.replaceAll("\\", "/").replaceAll(RegExp(r'^/+'), "");

    // Γ£à Normalize folder names to lowercase for consistency
    path = path.replaceAll("Uploads", "uploads");
    path = path.replaceAll("Profile_images", "profile_images");
    path = path.replaceAll("Cover_images", "cover_images");
    path = path.replaceAll("Page_images", "page_images");

    // Γ£à If only filename, prepend folder
    // Γ£à Only modify if NOT full URL
    if (!path.startsWith("http") && !path.contains("/")) {
      path = "uploads/page_images/$path";
    }

    // Γ£à Return complete HTTPS URL
    return "https://bigiluu.com/$path";
  }

  List<dynamic> list_pages() {
    final content = widget.post['content'];

    if (content is List) return content;

    if (content == null) return [];

    dynamic decoded;

    try {
      if (content is String) {
        final trimmed = content.trim();

        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          decoded = jsonDecode(trimmed);
        } else {
          return parseContent(content);
        }
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
    return widget.post['title']?.toString() ?? "";
  }

  List<dynamic> parseContent(dynamic rawContent) {
    try {
      if (rawContent is List) return rawContent;

      if (rawContent is Map && rawContent.containsKey('pages')) {
        return rawContent['pages'] ?? [];
      }

      if (rawContent is String) {
        final trimmed = rawContent.trim();

        final decoded = jsonDecode(trimmed);

        if (decoded is List) return decoded;
        if (decoded is Map && decoded.containsKey('pages')) {
          return decoded['pages'] ?? [];
        }
      }

      return [];
    } catch (e) {
      debugPrint("parseContent error: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFB11226);
    final caption = widget.post['caption']?.toString() ?? "";
    final hashtag =
        (widget.post['hastag'] ?? widget.post['hashtag'])?.toString().trim() ??
        "";

    final screenWidth = MediaQuery.of(context).size.width;
    double paddingHorizontal = screenWidth < 360 ? 12 : 20;

    final String postIdStr = widget.post['post_id']?.toString() ?? "";

    final imageUrl = fullUrl(widget.post['profile_image']);

    final coverUrl = fullUrl(widget.post['cover_img']);

    // ≡ƒÅå Badge Variants Logic
    String ack = (widget.post['acknowledgment'] ?? "").toString().toUpperCase();

    String badgeLabel = "";
    List<Color> badgeGradients = [Colors.white, Colors.white];
    Color themeBorderColor = Colors.white;
    Color themeSpineColor = Colors.white.withOpacity(0.2);

    dynamic titleStyleRaw = widget.post['title_style'] ?? {};
    Map<String, dynamic> titleStyle = {};
    if (titleStyleRaw is String && titleStyleRaw.isNotEmpty) {
      try {
        titleStyle = jsonDecode(titleStyleRaw);
      } catch (_) {}
    } else if (titleStyleRaw is Map) {
      titleStyle = Map<String, dynamic>.from(titleStyleRaw);
    }

    final double fontSize = (titleStyle['fontSize'] ?? 24).toDouble();
    final int colorValue = (titleStyle['color'] ?? 0xFFFFFFFF);
    final String fontFamily = titleStyle['fontFamily'] ?? "Roboto";

    // ≡ƒöÑ HANDLE EMPTY (WHITE)
    if (ack.isEmpty) {
      badgeLabel = ""; // no text OR you can put "NEW"
      badgeGradients = [Colors.white, Colors.white];
      themeBorderColor = Colors.white;
      themeSpineColor = Colors.white.withOpacity(0.1);
    }
    // ≡ƒÑç GOAT
    else if (ack == "GOAT") {
      badgeLabel = "GOAT";
      badgeGradients = [const Color(0xFFFFD700), const Color(0xFFDAA520)];
      themeBorderColor = const Color(0xFFFFD700);
      themeSpineColor = const Color(0xFFFFD700).withOpacity(0.2);
    }
    // ≡ƒÑê MERSAL
    else if (ack == "MERSAL") {
      badgeLabel = "MERSAL";
      badgeGradients = [const Color(0xFFE0E0E0), const Color(0xFF9E9E9E)];
      themeBorderColor = const Color(0xFFC0C0C0);
      themeSpineColor = const Color(0xFFE0E0E0).withOpacity(0.25);
    }
    // ≡ƒÑë THERI
    else if (ack == "THERI") {
      badgeLabel = "THERI";
      badgeGradients = [const Color(0xFFCD7F32), const Color(0xFF8B4513)];
      themeBorderColor = const Color(0xFFCD7F32);
      themeSpineColor = const Color(0xFFCD7F32).withOpacity(0.2);
    }
    return Container(
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
                          isPublicView: true, // ≡ƒöÑ ADD THIS
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
                        backgroundImage: imageUrl.isNotEmpty
                            ? NetworkImage(imageUrl)
                            : null,
                        child: imageUrl.isEmpty
                            ? Icon(Icons.person, color: Colors.grey)
                            : null,
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
                            "has published a Book",
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
              child: GestureDetector(
                onTap: () async {
                  if (_isOpeningPost) return;
                  setState(() => _isOpeningPost = true);

                  try {
                    final response = await http.get(
                      Uri.parse(
                        "https://bigiluu.com/api/posts/singlePost/$postIdStr",
                      ),
                    );

                    if (response.statusCode == 200) {
                      final jsonData = jsonDecode(response.body);

                      // ≡ƒöÑ FIX: correct path
                      final postData = jsonData['data'] ?? jsonData;
                      final rawContent = postData['content'];

                      List<dynamic> pages = parseContent(rawContent);

                      if (pages.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Content not available"),
                          ),
                        );
                        return;
                      }

                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullScreenPostViewer(
                            pages: pages,
                            username: postData['username'] ?? "",
                            profileImage: postData['profile_image'] ?? "",
                            postId: postIdStr,
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint("Error opening post: $e");
                  } finally {
                    if (mounted) {
                      setState(() => _isOpeningPost = false);
                    }
                  }
                },
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
                                  // Cover Image ΓÇö guard against empty/null URL
                                  CoverPreviewWidget(
                                    post: widget.post,
                                    fullUrl: fullUrl,
                                    fallback:
                                        (coverUrl.isEmpty ||
                                            !coverUrl.startsWith("http"))
                                        ? Container(
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFF1E1E2C),
                                                  Color(0xFF264060),
                                                ],
                                              ),
                                            ),
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                Icon(
                                                  Icons.auto_stories_rounded,
                                                  color: Colors.white
                                                      .withOpacity(0.05),
                                                  size: 180,
                                                ),
                                                Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const SizedBox(height: 60),
                                                    Text(
                                                      "Bigiluu",
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.2),
                                                        fontSize: 32,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        letterSpacing: 8,
                                                        fontFamily: 'Roboto',
                                                      ),
                                                    ),
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                            top: 8,
                                                          ),
                                                      width: 40,
                                                      height: 2,
                                                      color: Colors.white
                                                          .withOpacity(0.15),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          )
                                        : Image.network(
                                            coverUrl,
                                            fit: BoxFit.cover,
                                            loadingBuilder:
                                                (context, child, progress) {
                                                  if (progress == null)
                                                    return child;
                                                  return Container(
                                                    color: const Color(
                                                      0xFFF8F8F8,
                                                    ),
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
                                                    Color(0xFF1E1E2C),
                                                    Color(0xFF264060),
                                                  ],
                                                ),
                                              ),
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.auto_stories_rounded,
                                                    color: Colors.white
                                                        .withOpacity(0.05),
                                                    size: 180,
                                                  ),
                                                  Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      const SizedBox(
                                                        height: 60,
                                                      ),
                                                      Text(
                                                        "Bigiluu",
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(0.2),
                                                          fontSize: 32,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          letterSpacing: 8,
                                                          fontFamily: 'Roboto',
                                                        ),
                                                      ),
                                                      Container(
                                                        margin:
                                                            const EdgeInsets.only(
                                                              top: 8,
                                                            ),
                                                        width: 40,
                                                        height: 2,
                                                        color: Colors.white
                                                            .withOpacity(0.15),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
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

                                  // ≡ƒôû Book Title ΓÇö matching Cover Design exactly
                                  if ((widget.post['title']?.toString() ?? '')
                                      .isNotEmpty)
                                    Positioned(
                                      top: 15,
                                      left: 10,
                                      right: 10,
                                      child: SizedBox(
                                        width:
                                            MediaQuery.of(context).size.width *
                                            0.8,
                                        child: Text(
                                          widget.post['title']?.toString() ??
                                              '',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: fontSize,
                                            color: Color(colorValue),
                                            fontFamily: fontFamily,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Γ£à Dynamic Badge (Refined)
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
                        hashtag.startsWith("#") ? hashtag : "#$hashtag",
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
                    onTap: _sharePostWithImage,
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

class ExpandablePostImage extends StatelessWidget {
  final String imageUrl;
  const ExpandablePostImage({super.key, required this.imageUrl});

  void _showFullScreen(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.9), // Darker, more immersive
        pageBuilder: (context, _, __) =>
            FullScreenImageOverlay(imageUrl: imageUrl),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Add a subtle scale effect for a "pop out" feel
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showFullScreen(context),
      child: Hero(
        tag: imageUrl,
        child: Container(
          margin: const EdgeInsets.only(bottom: 32, top: 8),
          // Increased height for a true "portrait" feel (55% of screen height)
          height: MediaQuery.of(context).size.height * 0.55,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                blurRadius: 25,
                offset: const Offset(0, 15),
                spreadRadius: -5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover, // Fill the tall portrait container
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.black.withOpacity(0.03),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFB11226),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey.shade100,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image_rounded,
                        color: Colors.grey,
                        size: 40,
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Image unavailable",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
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

class FullScreenImageOverlay extends StatelessWidget {
  final String imageUrl;
  const FullScreenImageOverlay({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: Hero(
                tag: imageUrl,
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 6.0,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 30,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------------- FULL SCREEN TEXT VIEW ---------------- */

class FullScreenPostViewer extends StatefulWidget {
  final List pages;
  final String username;
  final String profileImage;
  final String postId; // Γ£à ADD THIS

  const FullScreenPostViewer({
    super.key,
    required this.pages,
    required this.username,
    required this.profileImage,
    required this.postId, // Γ£à ADD
  });
  @override
  State<FullScreenPostViewer> createState() => _FullScreenPostViewerState();
}

class _FullScreenPostViewerState extends State<FullScreenPostViewer> {
  int currentPage = 0;
  late PageController _controller;
  bool readerCounted = false;

  final GlobalKey _pageKey = GlobalKey();

  Future<void> _shareCurrentView() async {
    try {
      final boundary =
          _pageKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        await Share.share(
          "Read this post on Bigiluu: https://bigiluu.com/post/${widget.postId}",
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
        '${tempDir.path}/share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'Read this interesting story on Bigiluu: https://bigiluu.com/post/${widget.postId}',
      );
    } catch (e) {
      debugPrint("Error sharing: $e");
      await Share.share(
        "Read this post on Bigiluu: https://bigiluu.com/post/${widget.postId}",
      );
    }
  }

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
      print("≡ƒôè DEBUG: Incrementing reader for post: ${widget.postId}");

      final incrementResponse = await http
          .post(
            Uri.parse(
              "https://bigiluu.com/api/posts/incrementReader/${widget.postId}",
            ),
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print("ΓÜá∩╕Å incrementReader timeout");
              throw TimeoutException("Increment request timed out");
            },
          );

      print(
        "≡ƒôè DEBUG: Increment response status: ${incrementResponse.statusCode}",
      );
      print("≡ƒôè DEBUG: Increment response body: ${incrementResponse.body}");

      // Then, verify by fetching the updated post data
      await Future.delayed(const Duration(milliseconds: 500));

      final verifyResponse = await http
          .get(
            Uri.parse("https://bigiluu.com/api/posts/getPost/${widget.postId}"),
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print("ΓÜá∩╕Å getPost timeout");
              throw TimeoutException("Verify request timed out");
            },
          );

      if (verifyResponse.statusCode == 200) {
        final jsonData = jsonDecode(verifyResponse.body);
        final updatedPost = jsonData["data"];
        print(
          "Γ£à Verified - Current readers_count in DB: ${updatedPost['readers_count'] ?? 0}",
        );
      }
    } on TimeoutException catch (e) {
      print("ΓÜá∩╕Å Timeout in reader count: $e");
    } catch (e) {
      print("Γ¥î Reader count error: $e");
    }
  }

  String fullUrl(String? path) {
    if (path == null || path.isEmpty) return "";

    // Γ£à VERY IMPORTANT: DO NOT TOUCH FULL URL
    if (path.startsWith("http")) {
      return path; // ≡ƒöÑ DIRECT RETURN
    }

    path = path.replaceAll("\\", "/").replaceAll(RegExp(r'^/+'), "");

    if (path.startsWith("uploads/")) {
      return "https://bigiluu.com/$path";
    }

    return "https://bigiluu.com/uploads/page_images/$path";
  }

  String fixImageUrl(String? path) {
    if (path == null || path.isEmpty) return "";

    path = path.replaceAll("\\", "/").trim();

    // Γ¥î Fix double-prefixed bug
    if (path.contains("https://bigiluu.com/https://")) {
      path = path.replaceAll("https://bigiluu.com/", "");
    }

    // Γ£à Already full URL (S3 or correct)
    if (path.startsWith("http")) {
      return path;
    }

    // Γ£à Local image
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
                  "Page ${currentPage + 1} of ${widget.pages.length}",
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
                onPressed: _shareCurrentView,
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
                      value: (currentPage + 1) / widget.pages.length,
                      backgroundColor: textColor.withOpacity(0.05),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        brandColor.withOpacity(0.6),
                      ),
                      minHeight: 2,
                    ),
                  ),
                ),

                Expanded(
                  child: RepaintBoundary(
                    key: _pageKey,
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: widget.pages.length,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (index) async {
                        if (!mounted) return;
                        setState(() => currentPage = index);
                        final prefs = await SharedPreferences.getInstance();
                        prefs.setInt("reader_${widget.postId}", index);

                        if (!readerCounted && index >= 1) {
                          String key = "reader_counted_${widget.postId}";
                          bool alreadyCounted = prefs.getBool(key) ?? false;
                          if (!alreadyCounted) {
                            readerCounted = true;
                            await incrementReaderAndVerify();
                            if (!mounted) return;
                            prefs.setBool(key, true);
                          }
                        }
                      },
                      itemBuilder: (context, index) {
                        final page = widget.pages[index];
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
                              borderRadius: BorderRadius.circular(24),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return Stack(
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

                                      // Γ£à Big Watermark Logo
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
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minHeight: constraints.maxHeight,
                                          ),
                                          child: Center(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 60,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    _alignment ==
                                                        TextAlign.center
                                                    ? CrossAxisAlignment.center
                                                    : (_alignment ==
                                                              TextAlign.justify
                                                          ? CrossAxisAlignment
                                                                .stretch
                                                          : CrossAxisAlignment
                                                                .start),
                                                children: [
                                                  ...blocks.map<Widget>((
                                                    block,
                                                  ) {
                                                    if (block['type'] ==
                                                        'text') {
                                                      bool isHeadline =
                                                          block['isHeadline'] ??
                                                          false;
                                                      return Padding(
                                                        padding:
                                                            EdgeInsets.fromLTRB(
                                                              _horizontalPadding,
                                                              isHeadline
                                                                  ? 12
                                                                  : 0,
                                                              _horizontalPadding *
                                                                  0.8,
                                                              isHeadline
                                                                  ? 32
                                                                  : 24,
                                                            ),
                                                        child: SelectableText(
                                                          isHeadline
                                                              ? (block['text'] ??
                                                                        "")
                                                                    .toString()
                                                                    .toUpperCase()
                                                              : (block['text'] ??
                                                                    ""),
                                                          textAlign: _alignment,
                                                          style: TextStyle(
                                                            fontSize: isHeadline
                                                                ? _fontSize *
                                                                      1.3
                                                                : _fontSize,
                                                            fontFamily:
                                                                _fontFamily,
                                                            backgroundColor:
                                                                null,
                                                            color:
                                                                block['fontColor'] !=
                                                                    null
                                                                ? Color(
                                                                    block['fontColor'],
                                                                  )
                                                                : textColor.withOpacity(
                                                                    isHeadline
                                                                        ? 1.0
                                                                        : 0.85,
                                                                  ),
                                                            height: _lineHeight,
                                                            letterSpacing:
                                                                _letterSpacing,
                                                            fontWeight:
                                                                isHeadline
                                                                ? FontWeight
                                                                      .w900
                                                                : FontWeight
                                                                      .w400,
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                    if (block['type'] ==
                                                        'image') {
                                                      final imageUrl = fullUrl(
                                                        block['image'],
                                                      );

                                                      // Γ£à SAFETY 1: null / empty
                                                      if (imageUrl.isEmpty) {
                                                        return const SizedBox();
                                                      }

                                                      // Images take more width for a "Full Size" feel
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                            ),
                                                        child: ExpandablePostImage(
                                                          imageUrl: fixImageUrl(
                                                            block['image'],
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
                                              color: brandColor.withOpacity(
                                                0.05,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              "ΓÇö  ${index + 1}  ΓÇö",
                                              style: TextStyle(
                                                color: brandColor.withOpacity(
                                                  0.4,
                                                ),
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
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
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
