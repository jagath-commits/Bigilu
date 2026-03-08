import 'dart:async';
import 'dart:io' show Platform, File;
import 'package:bigilu/home.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PageBlock {
  String type;
  String? text;
  File? image;
  String? imageUrl; // 🔥 ADD THIS
  double? imageWidth;
  Offset? imagePosition; // 🔥 ADD THIS
  String? previousText;

  PageBlock.text(this.text)
    : type = "text",
      image = null,
      imageUrl = null,
      imageWidth = null,
      previousText = text;

  PageBlock.image(this.image)
    : type = "image",
      text = null,
      imageUrl = null,
      imageWidth = 200,
      imagePosition = const Offset(0, 0),
      previousText = null;

  PageBlock.networkImage(this.imageUrl)
    : type = "image",
      text = null,
      image = null,
      imageWidth = 200,
      imagePosition = const Offset(0, 0),
      previousText = null;
}

class PageData {
  double fontSize;
  String fontFamily;
  int fontColor;

  List<PageBlock> blocks;

  PageData({
    required this.fontSize,
    required this.fontFamily,
    required this.fontColor,
  }) : blocks = [PageBlock.text("")];
}

class WritePage extends StatefulWidget {
  final String? draftId; // optional
  final String? draftContent; // optional
  final String? draftCover;

  const WritePage({
    super.key,
    this.draftId,
    this.draftContent,
    this.draftCover, // 🔥 ADD THIS
  });

  @override
  State<WritePage> createState() => _WritePageState();
}

class _WritePageState extends State<WritePage> {
  String? _draftCoverImage;
  String? _draftId;

  // previously a fixed constant – use a getter so the limit updates
  // with the screen size/keyboard adjustments.
  double get _pageHeightLimit => MediaQuery.of(context).size.height * 0.65;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  int _getWordLimit(PageData page) {
    bool hasImage = page.blocks.any((block) => block.type == "image");

    return hasImage ? 120 : 250;
  }

  int _countWords(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  int _getMaxLines(double fontSize) {
    if (fontSize <= 16) return 25;
    if (fontSize <= 18) return 22;
    if (fontSize <= 20) return 20;
    if (fontSize <= 22) return 25;
    if (fontSize <= 24) return 17;
    if (fontSize <= 26) return 16;
    return 15; // font size 28
  }

  @override
  void initState() {
    super.initState();

    _draftId = widget.draftId;

    if (widget.draftContent != null) {
      _loadDraftContent(widget.draftContent!);
    }

    // ✅ INSERT COVER AS FIRST BLOCK
    if (widget.draftCover != null && widget.draftCover!.isNotEmpty) {
      _pages[0].blocks.insert(0, PageBlock.networkImage(widget.draftCover!));
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  // optionally assume an image will be added (useful when calculating before inserting)
  bool _doesTextOverflow(
    String text,
    PageData page,
    double maxWidth, {
    bool assumeImage = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: page.fontSize, fontFamily: page.fontFamily),
      ),
      maxLines: null,
      textDirection: TextDirection.ltr,
    );

    painter.layout(maxWidth: maxWidth);

    // consider the whole page: any image affects layout
    bool hasImage = assumeImage || page.blocks.any((b) => b.type == "image");

    // enforce line counts: 25 lines per page
    int actualLines = painter.computeLineMetrics().length;
    int allowedLines = 25;
    if (actualLines > allowedLines) return true;

    double allowedHeight = _pageHeightLimit;
    if (hasImage) {
      allowedHeight -= 200;
    }

    return painter.height > allowedHeight;
  }

  /// Rebalance all content from a given page index onwards
  /// This collects all text from that page to the end, then redistributes it
  /// ensuring proper page breaks and adding/removing pages as needed
  void _rebalancePagesFromIndex(int pageIndex) {
    if (pageIndex >= _pages.length) return;

    double maxWidth = MediaQuery.of(context).size.width * 0.75;

    // Collect all text blocks and images from this page onwards
    String allText = "";
    List<MapEntry<int, int>> imagePositions = []; // (pageIdx, blockIdx) pairs

    for (int p = pageIndex; p < _pages.length; p++) {
      for (int b = 0; b < _pages[p].blocks.length; b++) {
        final block = _pages[p].blocks[b];
        if (block.type == "text" && (block.text ?? "").isNotEmpty) {
          allText += (block.text ?? "") + "\n";
        } else if (block.type == "image") {
          imagePositions.add(MapEntry(p, b));
        }
      }
    }

    allText = allText.trim();

    // Clear all text blocks from this page onwards (keep images for now)
    for (int p = pageIndex; p < _pages.length; p++) {
      _pages[p].blocks.removeWhere((b) => b.type == "text");
    }

    // Redistribute all collected text starting from this page
    if (allText.isNotEmpty) {
      _distributeTextToPages(pageIndex, allText);
    }

    // Update all controllers from this page onwards
    for (int p = pageIndex; p < _pages.length; p++) {
      for (int b = 0; b < _pages[p].blocks.length; b++) {
        if (_pages[p].blocks[b].type == "text") {
          String key = "$p-$b";
          if (_controllers.containsKey(key)) {
            _controllers[key]!.text = _pages[p].blocks[b].text ?? "";
          } else {
            _controllers[key] = TextEditingController(
              text: _pages[p].blocks[b].text ?? "",
            );
            _focusNodes[key] = FocusNode();
          }
        }
      }
    }

    // Remove trailing empty pages
    while (_pages.length > 1 &&
        _pages.last.blocks.every(
          (b) => b.type != "text" || (b.text ?? "").trim().isEmpty,
        ) &&
        !_pages.last.blocks.any((b) => b.type == "image")) {
      _pages.removeLast();
      if (_currentPage >= _pages.length) {
        _currentPage = _pages.length - 1;
      }
    }
  }

  /// distribute [text] starting at [startPage] across pages, creating
  /// new pages as needed.  Guarantees no page ends up overflowing the visible
  /// area, even when [text] is very large (e.g. from a paste).
  void _distributeTextToPages(int startPage, String text) {
    double maxWidth = MediaQuery.of(context).size.width * 0.75;
    String remaining = text;
    int pageIdx = startPage;

    while (remaining.isNotEmpty) {
      // ensure page exists
      if (pageIdx >= _pages.length) {
        _pages.add(
          PageData(
            fontSize: _pages[0].fontSize,
            fontFamily: _pages[0].fontFamily,
            fontColor: _pages[0].fontColor,
          ),
        );
      }

      PageData page = _pages[pageIdx];

      // If this is a new page (not the starting page), clear empty blocks
      if (pageIdx > startPage) {
        page.blocks.removeWhere(
          (b) => b.type == "text" && (b.text ?? "").trim().isEmpty,
        );
      }

      // find or create a text block at end
      PageBlock? lastBlock;
      for (var b in page.blocks.reversed) {
        if (b.type == "text") {
          lastBlock = b;
          break;
        }
      }
      if (lastBlock == null) {
        page.blocks.add(PageBlock.text(""));
        lastBlock = page.blocks.last;
      }

      String existing = lastBlock.text ?? "";
      String candidate = existing + remaining;

      if (!_doesTextOverflow(candidate, page, maxWidth)) {
        // whole remainder fits on this page
        lastBlock.text = candidate;
        remaining = "";
      } else {
        // need to split; binary search for largest prefix that fits
        int low = 0, high = remaining.length;
        while (low < high) {
          int mid = (low + high + 1) ~/ 2;
          String prefix = existing + remaining.substring(0, mid);
          if (_doesTextOverflow(prefix, page, maxWidth)) {
            high = mid - 1;
          } else {
            low = mid;
          }
        }
        // low characters of remaining can fit
        if (low == 0) {
          // should not happen (means single char doesn't fit)
          // to avoid infinite loop, forcibly move one char
          low = 1;
        }
        String fitPart = remaining.substring(0, low);
        lastBlock.text = existing + fitPart;
        remaining = remaining.substring(low);
        pageIdx++;
      }
    }
  }

  void _handleTextChange(String value, int pageIndex, int blockIndex) {
  final page = _pages[pageIndex];
  double maxWidth = MediaQuery.of(context).size.width * 0.75;

  _pages[pageIndex].blocks[blockIndex].text = value;
  _controllers["$pageIndex-$blockIndex"]?.text = value;
  _pages[pageIndex].blocks[blockIndex].previousText = value;

  int oldPageCount = _pages.length;

  if (_doesTextOverflow(value, page, maxWidth)) {
    _rebalancePagesFromIndex(pageIndex);

    /// 🔥 if a new page was created
    if (_pages.length > oldPageCount) {
      int newPageIndex = pageIndex + 1;

      setState(() {
        _currentPage = newPageIndex;
      });

      /// 🔥 jump to the new page
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(newPageIndex);
      });

      /// 🔥 move cursor to first text field
      Future.delayed(const Duration(milliseconds: 100), () {
        String key = "$newPageIndex-0";

        if (!_controllers.containsKey(key)) {
          _controllers[key] = TextEditingController(
            text: _pages[newPageIndex].blocks.first.text ?? "",
          );
        }

        if (!_focusNodes.containsKey(key)) {
          _focusNodes[key] = FocusNode();
        }

        FocusScope.of(context).requestFocus(_focusNodes[key]);
      });
    }
  } else {
    _pullContentUpIfSpace(pageIndex);
  }

  /// remove empty pages
  while (_pages.length > 1 &&
      _pages.last.blocks.every(
        (b) => b.type != "text" || (b.text ?? "").trim().isEmpty,
      ) &&
      !_pages.last.blocks.any((b) => b.type == "image")) {
    _pages.removeLast();
    if (_currentPage >= _pages.length) {
      _currentPage = _pages.length - 1;
    }
  }
}

  /// Pull content from next page if current page has space
  void _pullContentUpIfSpace(int pageIndex) {
    if (pageIndex >= _pages.length - 1) return; // No next page

    double maxWidth = MediaQuery.of(context).size.width * 0.75;
    var currentPage = _pages[pageIndex];
    var nextPage = _pages[pageIndex + 1];

    // Calculate current page usage
    String currentText = "";
    for (var b in currentPage.blocks) {
      if (b.type == "text") currentText += (b.text ?? "") + "\n";
    }
    currentText = currentText.trim();

    // If current page has space, try to pull one block from next page
    if (!_doesTextOverflow(currentText, currentPage, maxWidth)) {
      var nextTextBlocks = nextPage.blocks
          .where((b) => b.type == "text" && (b.text ?? "").trim().isNotEmpty)
          .toList();

      if (nextTextBlocks.isNotEmpty) {
        // Check if next page will still have content
        bool canMove =
            nextTextBlocks.length > 1 ||
            nextPage.blocks.any((b) => b.type == "image");

        if (canMove) {
          // Try to move first block to current page
          var blockToMove = nextTextBlocks.first;
          String testText = currentText + "\n" + (blockToMove.text ?? "");

          if (!_doesTextOverflow(testText, currentPage, maxWidth)) {
            // It fits! Move the block
            currentPage.blocks.add(PageBlock.text(blockToMove.text ?? ""));
            nextPage.blocks.remove(blockToMove);

            // Update controller
            int newBlockIndex = currentPage.blocks.length - 1;
            String newKey = "$pageIndex-$newBlockIndex";
            _controllers[newKey] = TextEditingController(
              text: blockToMove.text ?? "",
            );
            _focusNodes[newKey] = FocusNode();

            // Recursively try to pull more if still has space
            _pullContentUpIfSpace(pageIndex);
          }
        }
      }
    }
  }

  Future<void> _postDraft() async {
    try {
      List<Map<String, dynamic>> pagesJson = [];

      for (var page in _pages) {
        List<Map<String, dynamic>> blocksJson = [];

        for (var block in page.blocks) {
          blocksJson.add({
            "type": block.type,
            "text": block.text,
            "image": block.image?.path.split('/').last,
            "imageWidth": block.imageWidth,
          });
        }

        pagesJson.add({
          "fontSize": page.fontSize,
          "fontFamily": page.fontFamily,
          "fontColor": page.fontColor,
          "blocks": blocksJson,
        });
      }

      final contentJson = jsonEncode(pagesJson);

      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString("user_id");

      // ✅ ALWAYS assign
      String url = "https://bigiluu.com/api/posts/createPost";

      Map<String, dynamic> body = {
        "user_id": currentUserId,
        "content": contentJson,
        "caption": "",
      };

      // If draft exists → delete first
      if (widget.draftId != null) {
        await http.delete(
          Uri.parse(
            "https://bigiluu.com/api/draft/deleteDraft/${widget.draftId}",
          ),
        );
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Post published successfully!")),
        );

        Navigator.pop(context);
      }
    } catch (e) {
      print("Error posting draft: $e");
    }
  }

  void _loadDraftContent(String content) {
    try {
      List<dynamic> decoded = jsonDecode(content);

      _pages = [];

      for (var page in decoded) {
        PageData pageData = PageData(
          fontSize: (page['fontSize'] ?? 20).toDouble(),
          fontFamily: page['fontFamily'] ?? "Roboto",
          fontColor: page['fontColor'] ?? Colors.black.value,
        );

        pageData.blocks.clear();

        for (var block in page['blocks']) {
          if (block['type'] == "text") {
            pageData.blocks.add(PageBlock.text(block['text'] ?? ""));
          }

          if (block['type'] == "image") {
            final imageName = block['image'];
            final width = (block['imageWidth'] ?? 200).toDouble();
            final posX = (block['imagePosX'] ?? 0).toDouble();
            final posY = (block['imagePosY'] ?? 0).toDouble();

            if (imageName != null && imageName.toString().trim().isNotEmpty) {
              final imageUrl =
                  "https://bigiluu.com/uploads/draft_covers/$imageName";

              final imgBlock = PageBlock.networkImage(imageUrl);
              imgBlock.imageWidth = width;
              imgBlock.imagePosition = Offset(posX, posY);
              pageData.blocks.add(imgBlock);
            }
          }
        }

        _pages.add(pageData);
      }

      setState(() {
        _currentPage = 0;
      });
    } catch (e) {
      print("Draft load error: $e");
    }
  }

  final ImagePicker _imagePicker = ImagePicker();

  List<PageData> _pages = [
    PageData(fontSize: 22, fontFamily: "Roboto", fontColor: Colors.black.value),
  ];

  Future<void> saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");

    final uri = Uri.parse("https://bigiluu.com/api/draft/saveDraft");

    var request = http.MultipartRequest("POST", uri);

    request.fields["user_id"] = userId ?? "";

    if (widget.draftId != null) {
      request.fields["draft_id"] = widget.draftId!;
    }

    List<Map<String, dynamic>> pagesJson = [];

    for (var page in _pages) {
      List<Map<String, dynamic>> blocksJson = [];

      for (var block in page.blocks) {
        String? imageName;

        // ✅ CASE 1: New image selected from gallery
        if (block.type == "image" && block.image != null) {
          request.files.add(
            await http.MultipartFile.fromPath("page_images", block.image!.path),
          );

          imageName = block.image!.path.split('/').last;
        }
        // ✅ CASE 2: Already saved network image (editing draft)
        else if (block.type == "image" && block.imageUrl != null) {
          imageName = block.imageUrl!.split('/').last;
        }

        blocksJson.add({
          "type": block.type,
          "text": block.text,
          "image": imageName,
          "imageWidth": block.imageWidth,
          "imagePosX": block.imagePosition?.dx,
          "imagePosY": block.imagePosition?.dy,
        });
      }

      pagesJson.add({
        "fontSize": page.fontSize,
        "fontFamily": page.fontFamily,
        "fontColor": page.fontColor,
        "blocks": blocksJson,
      });
    }

    request.fields["content"] = jsonEncode(pagesJson);

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    print("STATUS: ${response.statusCode}");
    print("BODY: ${response.body}");
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // 🔥 VERY IMPORTANT
      if (data["draft_id"] != null) {
        _draftId = data["draft_id"]; // STORE IT
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Draft Saved")));
    }
  }

  Future<void> _pickImageForPage(int index) async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        // before inserting, make sure current page can fit the image
        double maxWidth = MediaQuery.of(context).size.width * 0.75;
        // combine all existing text in the page
        String combinedText = _pages[index].blocks
            .where((b) => b.type == "text")
            .map((b) => b.text ?? "")
            .join("\n");

        bool willOverflow = _doesTextOverflow(
          combinedText,
          _pages[index],
          maxWidth,
          assumeImage: true,
        );
        int targetPage = index;
        if (willOverflow) {
          targetPage = index + 1;
          if (targetPage >= _pages.length) {
            _pages.add(
              PageData(
                fontSize: _pages[index].fontSize,
                fontFamily: _pages[index].fontFamily,
                fontColor: _pages[index].fontColor,
              ),
            );
          }
        }

        _pages[targetPage].blocks.add(PageBlock.image(File(image.path)));
        // Add new text block after image
        _pages[targetPage].blocks.add(PageBlock.text(""));

        if (willOverflow) {
          // navigate to new page
          Future.microtask(() {
            _pageController.animateToPage(
              targetPage,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
            );
          });
        }
      });
    }
  }

  void _removeImageBlock(int pageIndex, int blockIndex) {
    setState(() {
      final blocks = _pages[pageIndex].blocks;

      // simply remove the image – do NOT delete the following text
      blocks.removeAt(blockIndex);

      // if removing left two adjacent text blocks, merge them
      for (int i = 0; i < blocks.length - 1; i++) {
        if (blocks[i].type == "text" && blocks[i + 1].type == "text") {
          blocks[i].text =
              (blocks[i].text ?? "") + '\n' + (blocks[i + 1].text ?? "");
          blocks.removeAt(i + 1);
          break;
        }
      }
    });
  }

  void _deleteCurrentPage() {
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("At least one page is required")),
      );
      return;
    }

    setState(() {
      _pages.removeAt(_currentPage);

      // Move to previous page if needed
      if (_currentPage >= _pages.length) {
        _currentPage = _pages.length - 1;
      }

      _pageController.jumpToPage(_currentPage);

      // Update controllers for pages after the deleted one
      for (int p = _currentPage; p < _pages.length; p++) {
        for (int b = 0; b < _pages[p].blocks.length; b++) {
          if (_pages[p].blocks[b].type == "text") {
            String oldKey = "${p + 1}-$b";
            String newKey = "$p-$b";
            if (_controllers.containsKey(oldKey)) {
              _controllers[newKey] = _controllers.remove(oldKey)!;
              _focusNodes[newKey] = _focusNodes.remove(oldKey)!;
            }
          }
        }
      }
    });
  }

  double _fontSize = 22;
  Color _fontColor = Colors.black;
  String _fontFamily = "Roboto";
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<String> _fontFamilies = [
    "Roboto",
    "Merienda",
    "Courier New",
    "Times New Roman",
    "Arial",
    "Lobster",
  ];

  final List<Color> _fontColors = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.brown,
  ];

  void _addNewPage() {
    setState(() {
      _pages.add(
        PageData(
          fontSize: 22,
          fontFamily: "Roboto",
          fontColor: Colors.black.value,
        ),
      );
      _pageController.jumpToPage(_pages.length - 1);
      _currentPage = _pages.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        await saveDraft();
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          title: Row(
            children: [
              Image.asset(
                "assets/images/bigilu_logo21.png",
                height: 50,
                fit: BoxFit.contain,
              ),

              const Spacer(), // pushes buttons to right

              TextButton(
                onPressed: () async {
                  await saveDraft();

                  // Go back and tell profile to refresh
                  Navigator.pop(context, true);
                },
                child: const Text(
                  "Save Draft",
                  style: TextStyle(fontSize: 16, color: Color(0xFF800000)),
                ),
              ),

              const SizedBox(width: 8),

              TextButton(
                onPressed: () {
                  final route = Platform.isIOS
                      ? CupertinoPageRoute(
                          builder: (_) => CoverEditorPage(
                            pages: _pages,
                            draftId: widget.draftId,
                          ),
                        )
                      : MaterialPageRoute(
                          builder: (_) => CoverEditorPage(
                            pages: _pages,
                            draftId: widget.draftId,
                          ),
                        );

                  Navigator.push(context, route);
                },
                child: const Text(
                  "Next",
                  style: TextStyle(fontSize: 16, color: Color(0xFF800000)),
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(size.width * 0.04),
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (index) {
                        setState(() => _currentPage = index);
                      },
                      itemBuilder: (context, index) {
                        return Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(size.width * 0.03),
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
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.65,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List.generate(
                                  _pages[index].blocks.length,
                                  (blockIndex) {
                                    final block =
                                        _pages[index].blocks[blockIndex];
                                    if (block.type == "text") {
                                      String key = "$index-$blockIndex";

                                      if (!_controllers.containsKey(key)) {
                                        _controllers[key] =
                                            TextEditingController(
                                              text: block.text ?? "",
                                            );
                                      }

                                      if (!_focusNodes.containsKey(key)) {
                                        _focusNodes[key] = FocusNode();
                                      }

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: TextField(
                                          controller: _controllers[key],
                                          focusNode: _focusNodes[key],
                                          onChanged: (value) {
                                            _handleTextChange(
                                              value,
                                              index,
                                              blockIndex,
                                            );
                                          },
                                          maxLines: null,
                                          style: TextStyle(
                                            fontSize: _pages[index].fontSize,
                                            fontFamily:
                                                _pages[index].fontFamily,
                                            color: Color(
                                              _pages[index].fontColor,
                                            ),
                                          ),
                                          decoration: InputDecoration(
                                            hintText: blockIndex == 0
                                                ? "Write your heart..."
                                                : null,
                                            border: InputBorder.none,
                                          ),
                                        ),
                                      );
                                    }

                                    if (block.type == "image") {
                                      Widget imageWidget;
                                      if (block.image != null) {
                                        imageWidget = Image.file(
                                          block.image!,
                                          width: 200,
                                          height: 200,
                                          fit: BoxFit.contain,
                                        );
                                      } else if (block.imageUrl != null &&
                                          block.imageUrl!.isNotEmpty) {
                                        imageWidget = Image.network(
                                          block.imageUrl!,
                                          width: 200,
                                          height: 200,
                                          fit: BoxFit.contain,
                                        );
                                      } else {
                                        return const SizedBox();
                                      }
                                      return Stack(
                                        alignment: Alignment.topRight,
                                        children: [
                                          Center(child: imageWidget),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            onPressed: () => _removeImageBlock(
                                              index,
                                              blockIndex,
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    return const SizedBox();
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF800000),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "Page ${_currentPage + 1} / ${_pages.length}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: FloatingActionButton(
                        backgroundColor: const Color(0xFF800000),
                        heroTag: "deletePage",
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text("Delete Page?"),
                              content: const Text(
                                "This action cannot be undone.",
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _deleteCurrentPage();
                                  },
                                  child: const Text(
                                    "Delete",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton(
                        backgroundColor: const Color(0xFF800000),
                        onPressed: _addNewPage,
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.font_download),
                    onSelected: (value) {
                      setState(() {
                        _fontFamily = value;
                        _pages[_currentPage].fontFamily = value;
                      });
                    },
                    itemBuilder: (context) => _fontFamilies
                        .map(
                          (font) => PopupMenuItem(
                            value: font,
                            child: Text(
                              font,
                              style: TextStyle(fontFamily: font),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  PopupMenuButton<Color>(
                    icon: const Icon(Icons.color_lens),
                    onSelected: (value) {
                      setState(() {
                        _fontColor = value;
                        _pages[_currentPage].fontColor = value.value;
                      });
                    },
                    itemBuilder: (context) => _fontColors
                        .map(
                          (color) => PopupMenuItem(
                            value: color,
                            child: CircleAvatar(
                              backgroundColor: color,
                              radius: 10,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoverEditorPage extends StatefulWidget {
  final List<PageData> pages;
  final String? draftId;

  const CoverEditorPage({super.key, required this.pages, this.draftId});

  @override
  State<CoverEditorPage> createState() => _CoverEditorPageState();
}

class _CoverEditorPageState extends State<CoverEditorPage> {
  final TextEditingController _titleController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? _coverImage;

  double _fontSize = 28;
  Color _fontColor = Colors.white;
  String _fontFamily = "Roboto";

  Offset _textPosition = const Offset(0.5, 0.4);

  final List<String> _fontFamilies = [
    "Roboto",
    "Merienda",
    "Courier New",
    "Times New Roman",
    "Arial",
    "Lobster",
  ];

  final List<Color> _colors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.yellow,
    Colors.green,
    Colors.orange,
  ];

  Future<void> _pickCoverImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      setState(() {
        _coverImage = File(picked.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Design Cover"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostPage(
                    pages: widget.pages,
                    draftId: widget.draftId,
                    coverImage: _coverImage,
                    title: _titleController.text,
                    titleFontSize: _fontSize,
                    titleColor: _fontColor,
                    titleFontFamily: _fontFamily,
                    titlePosition: _textPosition,
                  ),
                ),
              );
            },
            child: const Text(
              "Next",
              style: TextStyle(fontSize: 16, color: Color(0xFF800000)),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// COVER PREVIEW AREA
            GestureDetector(
              onTap: _pickCoverImage,
              child: Container(
                width: size.width * 0.7,
                height: size.height * 0.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade300,
                ),
                child: Stack(
                  children: [
                    // Cover Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _coverImage != null
                          ? Image.file(
                              _coverImage!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : const Center(child: Icon(Icons.image, size: 60)),
                    ),

                    // DRAGGABLE TITLE
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Positioned(
                              top: 30,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Text(
                                  _titleController.text,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: _fontSize,
                                    color: _fontColor,
                                    fontFamily: _fontFamily,
                                    fontWeight: FontWeight.bold,
                                    shadows: const [
                                      Shadow(
                                        blurRadius: 8,
                                        color: Colors.black,
                                        offset: Offset(2, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// TITLE INPUT
            TextField(
              controller: _titleController,
              onChanged: (value) => setState(() {}),
              decoration: const InputDecoration(
                hintText: "Enter Book Title",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            /// FONT SIZE
            Row(
              children: [
                const Text("Font Size"),
                Expanded(
                  child: Slider(
                    min: 16,
                    max: 60,
                    value: _fontSize,
                    onChanged: (value) {
                      setState(() => _fontSize = value);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            /// FONT FAMILY
            DropdownButton<String>(
              value: _fontFamily,
              isExpanded: true,
              items: _fontFamilies
                  .map(
                    (font) => DropdownMenuItem(
                      value: font,
                      child: Text(font, style: TextStyle(fontFamily: font)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _fontFamily = value!);
              },
            ),

            const SizedBox(height: 10),

            /// COLOR PICKER
            Wrap(
              spacing: 10,
              children: _colors
                  .map(
                    (color) => GestureDetector(
                      onTap: () => setState(() => _fontColor = color),
                      child: CircleAvatar(backgroundColor: color, radius: 15),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class PostPage extends StatefulWidget {
  final List<PageData> pages;
  final String? draftId; // 🔥 ADD THIS

  final File? coverImage;
  final String? title;
  final double? titleFontSize;
  final Color? titleColor;
  final String? titleFontFamily;
  final Offset? titlePosition;

  const PostPage({
    super.key,
    required this.pages,
    this.draftId,
    this.coverImage,
    this.title,
    this.titleFontSize,
    this.titleColor,
    this.titleFontFamily,
    this.titlePosition,
  });

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _hashtagController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  File? _pickedImage;

  Future<void> _pickCoverImage() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  void initState() {
    super.initState();
    print("Draft ID in PostPage: ${widget.draftId}");
  }

  Future<void> _submitPost() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");

    final uri = Uri.parse("https://bigiluu.com/api/posts/createPost");

    var request = http.MultipartRequest("POST", uri);

    request.fields["user_id"] = userId ?? "";
    String? coverImageName;

    if (widget.coverImage != null) {
      File? finalCover = _pickedImage ?? widget.coverImage;

      if (finalCover != null) {
        request.files.add(
          await http.MultipartFile.fromPath("cover_images", finalCover.path),
        );

        coverImageName = finalCover.path.split('/').last;
      }
    }
    request.fields["caption"] = _captionController.text;
    String tagText = _hashtagController.text.trim();

    // ✅ If user didn't enter hashtag → auto generate
    if (tagText.isEmpty) {
      List<String> words = [];

      for (var page in widget.pages) {
        for (var block in page.blocks) {
          if (block.type == "text" && block.text != null) {
            words.addAll(
              block.text!
                  .toLowerCase()
                  .replaceAll(RegExp(r'[^\w\s]'), '')
                  .split(" "),
            );
          }
        }
      }

      // Remove small words & duplicates
      words = words
          .where((w) => w.length > 4) // only meaningful words
          .toSet()
          .take(5) // limit to 5 hashtags
          .toList();

      tagText = words.map((w) => "#$w").join(" ");
    }

    // If user typed without #
    if (tagText.isNotEmpty && !tagText.startsWith("#")) {
      tagText = "#$tagText";
    }

    request.fields["hastag"] = tagText;

    List<Map<String, dynamic>> pagesJson = [];

    for (int i = 0; i < widget.pages.length; i++) {
      List<Map<String, dynamic>> blocksJson = [];

      for (int j = 0; j < widget.pages[i].blocks.length; j++) {
        final block = widget.pages[i].blocks[j];

        String? imageServerPath;

        if (block.type == "image" && block.image != null) {
          request.files.add(
            await http.MultipartFile.fromPath("page_images", block.image!.path),
          );

          imageServerPath = block.image!.path.split('/').last;
        }

        blocksJson.add({
          "type": block.type,
          "text": block.text,
          "image": imageServerPath,
          "imageWidth": block.imageWidth,
          "imagePosX": block.imagePosition?.dx,
          "imagePosY": block.imagePosition?.dy,
        });
      }

      pagesJson.add({
        "fontSize": widget.pages[i].fontSize,
        "fontFamily": widget.pages[i].fontFamily,
        "fontColor": widget.pages[i].fontColor,
        "blocks": blocksJson,
      });
    }

    final fullContent = {
      "title": widget.title,
      "titleFontSize": widget.titleFontSize,
      "titleColor": widget.titleColor?.value,
      "titleFontFamily": widget.titleFontFamily,
      "titlePositionX": widget.titlePosition?.dx,
      "titlePositionY": widget.titlePosition?.dy,
      "coverImage": coverImageName,
      "pages": pagesJson,
    };

    request.fields["content"] = jsonEncode(fullContent);
    request.fields["title"] = widget.title ?? "";

    request.fields["titleFontSize"] = widget.titleFontSize?.toString() ?? "28";

    request.fields["titleColor"] =
        widget.titleColor?.value.toString() ?? Colors.white.value.toString();

    request.fields["titleFontFamily"] = widget.titleFontFamily ?? "Roboto";

    request.fields["titlePositionX"] =
        widget.titlePosition?.dx.toString() ?? "0.5";

    request.fields["titlePositionY"] =
        widget.titlePosition?.dy.toString() ?? "0.4";

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    print("STATUS: ${response.statusCode}");
    print("BODY: ${response.body}");

    if (response.statusCode == 200) {
      if (widget.draftId != null) {
        await http.delete(
          Uri.parse(
            "https://bigiluu.com/api/draft/deleteDraft/${widget.draftId}",
          ),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Post Created Successfully")),
      );

      final route = Platform.isIOS
          ? CupertinoPageRoute(builder: (_) => const HomePage())
          : MaterialPageRoute(builder: (_) => const HomePage());

      Navigator.pushAndRemoveUntil(context, route, (route) => false);
    } else {
      print("Post Failed");
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(title: const Text("Create Post")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(size.width * 0.04),
        child: Column(
          children: [
            const SizedBox(height: 20),
            SizedBox(
              width: size.width * 0.7,
              height: size.height * 0.5,
              child: PageView.builder(
                itemCount: widget.pages.length + 1, // +1 for cover
                itemBuilder: (context, index) {
                  // 🟣 FIRST PAGE = COVER
                  if (index == 0) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(4, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            if (widget.coverImage != null)
                              Image.file(
                                widget.coverImage!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              )
                            else
                              Container(color: Colors.grey.shade300),

                            if (widget.title != null)
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return Stack(
                                    children: [
                                      Positioned(
                                        top: 30,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: Text(
                                            widget.title ?? "",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize:
                                                  widget.titleFontSize ?? 28,
                                              color:
                                                  widget.titleColor ??
                                                  Colors.white,
                                              fontFamily:
                                                  widget.titleFontFamily ??
                                                  "Roboto",
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  // 🔵 OTHER PAGES = CONTENT
                  final page = widget.pages[index - 1];

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0xFF800000),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      itemCount: page.blocks.length,
                      itemBuilder: (context, blockIndex) {
                        final block = page.blocks[blockIndex];

                        if (block.type == "text") {
                          return Text(
                            block.text ?? "",
                            style: TextStyle(
                              fontSize: page.fontSize,
                              fontFamily: page.fontFamily,
                              color: Color(page.fontColor),
                            ),
                          );
                        }

                        // IMAGE
                        if (block.type == "image") {
                          Widget imageWidget;
                          if (block.image != null) {
                            imageWidget = Image.file(
                              block.image!,
                              width: 200,
                              height: 200,
                              fit: BoxFit.contain,
                            );
                          } else if (block.imageUrl != null &&
                              block.imageUrl!.isNotEmpty) {
                            imageWidget = Image.network(
                              block.imageUrl!,
                              width: 200,
                              height: 200,
                              fit: BoxFit.contain,
                            );
                          } else {
                            return const SizedBox();
                          }
                          return Center(child: imageWidget);
                        }
                        return const SizedBox();
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _captionController,
              decoration: InputDecoration(
                hintText: "Write a caption...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _hashtagController,
              decoration: InputDecoration(
                hintText: "Add hashtags... (e.g. #book #love #story)",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _submitPost();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF800000),
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                "Post",
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
