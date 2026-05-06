import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CoverPreviewWidget extends StatefulWidget {
  final Map post;
  final String Function(String?) fullUrl;
  final Widget fallback;

  const CoverPreviewWidget({
    Key? key,
    required this.post,
    required this.fullUrl,
    required this.fallback,
  }) : super(key: key);

  @override
  State<CoverPreviewWidget> createState() => _CoverPreviewWidgetState();
}

class _CoverPreviewWidgetState extends State<CoverPreviewWidget> {
  bool _isLoading = false;
  Map? _fullPost;

  @override
  void initState() {
    super.initState();
    _checkAndFetchContent();
  }

  Map get _currentPost => _fullPost ?? widget.post;

  Future<void> _checkAndFetchContent() async {
    final content = widget.post['content'];
    final coverImg = widget.post['cover_img']?.toString() ?? '';
    if (content == null && coverImg.isEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        final postId = widget.post['post_id']?.toString() ?? '';
        if (postId.isNotEmpty) {
          final response = await http.get(
            Uri.parse('https://bigiluu.com/api/posts/singlePost/$postId'),
          );
          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);
            final fetchedPost = decoded['data'];
            if (mounted && fetchedPost != null) {
              setState(() {
                _fullPost = fetchedPost;
              });
            }
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool isManuPost() {
    final post = _currentPost;
    if (post['category'] == 'Manu') return true;
    final content = post['content'];
    if (content == null) return false;
    dynamic decoded;
    try {
      if (content is String) {
        final trimmed = content.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          decoded = jsonDecode(trimmed);
        } else {
          return false;
        }
      } else {
        decoded = content;
      }
    } catch (_) {
      return false;
    }
    if (decoded is Map && decoded['category'] == 'Manu') return true;
    if (decoded is Map &&
        decoded['pages'] is List &&
        decoded['pages'].isNotEmpty) {
      if (decoded['pages'][0] is Map &&
          decoded['pages'][0]['category'] == 'Manu')
        return true;
    }
    if (decoded is List && decoded.isNotEmpty) {
      if (decoded[0] is Map && decoded[0]['category'] == 'Manu') return true;
    }

    final coverImg =
        post['cover_img']?.toString() ?? post['coverUrl']?.toString() ?? '';
    final title = post['title']?.toString().trim() ?? '';
    if (coverImg.isEmpty && title.isEmpty) {
      return true;
    }

    return false;
  }

  List<dynamic> list_pages() {
    final post = _currentPost;
    final content = post['content'];
    if (content is List) return content;
    if (content == null) return [];
    dynamic decoded;
    try {
      if (content is String) {
        final trimmed = content.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          decoded = jsonDecode(trimmed);
        } else {
          return [];
        }
      } else {
        decoded = content;
      }
    } catch (_) {
      return [];
    }
    if (decoded is List) return decoded;
    if (decoded is Map && decoded.containsKey('pages')) {
      final p = decoded['pages'];
      if (p is String) {
        try {
          return jsonDecode(p);
        } catch (_) {
          return [];
        }
      }
      return p ?? [];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: const Color(0xFFFDFBF7),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.grey, strokeWidth: 2),
        ),
      );
    }

    if (!isManuPost()) return widget.fallback;

    List<dynamic> pages = list_pages();
    if (pages.isEmpty) {
      return Container(
        color: const Color(0xFFFDFBF7),
        child: const Center(
          child: Icon(Icons.article_outlined, color: Colors.grey, size: 60),
        ),
      );
    }

    final firstPage = pages[0];
    final double pageFontSize = (firstPage['fontSize'] ?? 14).toDouble();
    final String pageFontFamily = firstPage['fontFamily'] ?? 'Roboto';
    Color pageFontColor = Colors.black87;
    if (firstPage['fontColor'] != null) {
      try {
        pageFontColor = Color(
          int.parse(firstPage['fontColor'].toString()),
        ).withOpacity(1.0);
      } catch (_) {}
    }

    // ✅ GET TITLE
    final String title = _currentPost['title']?.toString() ?? '';

    List<Widget> blockWidgets = [];
    final blocks = firstPage['blocks'] ?? [];

    // ✅ TITLE BANNER (NEW)
    if (title.isNotEmpty) {
      blockWidgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade100, Colors.orange.shade50],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    // Add a professional header
    blockWidgets.add(
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.black.withOpacity(0.05), width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 14,
              color: Colors.black.withOpacity(0.3),
            ),
            const SizedBox(width: 6),
            Text(
              "MANU",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: Colors.black.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );

    for (var b in blocks) {
      if (b['type'] == 'text') {
        String text = b['text']?.toString() ?? '';
        if (text.trim().isEmpty) continue;

        bool isHeadline = b['isHeadline'] == true || b['isHeadline'] == 'true';
        double bFontSize = (b['fontSize'] ?? pageFontSize).toDouble();
        String bFontFamily = b['fontFamily'] ?? pageFontFamily;
        Color bFontColor = pageFontColor;
        if (b['fontColor'] != null) {
          try {
            bFontColor = Color(
              int.parse(b['fontColor'].toString()),
            ).withOpacity(1.0);
          } catch (_) {}
        }

        blockWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Text(
              text,
              style: TextStyle(
                fontSize: isHeadline ? bFontSize * 1.2 : bFontSize * 0.85,
                fontWeight: isHeadline ? FontWeight.w800 : FontWeight.w400,
                fontFamily: bFontFamily,
                color: bFontColor.withOpacity(0.85),
                height: 1.6,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      } else if (b['type'] == 'image') {
        String imgPath =
            b['image']?.toString() ?? b['imageUrl']?.toString() ?? '';
        if (imgPath.isNotEmpty) {
          blockWidgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.fullUrl(imgPath),
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
          );
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7),
        image: const DecorationImage(
          image: NetworkImage(
            'https://www.transparenttextures.com/patterns/paper-fibers.png',
          ),
          repeat: ImageRepeat.repeat,
          opacity: 0.04,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: blockWidgets,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 60,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFDFBF7).withOpacity(0.0),
                    const Color(0xFFFDFBF7).withOpacity(0.8),
                    const Color(0xFFFDFBF7),
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
