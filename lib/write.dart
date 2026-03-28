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
import 'package:google_fonts/google_fonts.dart';

class PageBlock {
  String type;
  String? text;
  File? image;
  String? imageUrl;
  double? imageWidth;
  Offset? imagePosition;
  String? previousText;
  bool isHeadline;
  int? fontColor; // 🔥 BLOCK COLOR
  double? fontSize; // 🔥 BLOCK FONT SIZE
  String? fontFamily; // 🔥 BLOCK FONT FAMILY
  double? lineSpacing;
  double? letterSpacing;
  TextAlign? textAlign;

  PageBlock({
    required this.type,
    this.text,
    this.imageUrl,
    this.imagePosition,
    this.isHeadline = false,
    this.fontSize,
    this.fontFamily,
    this.fontColor,
    this.lineSpacing,
    this.letterSpacing,
    this.textAlign,
  });

  PageBlock.text(
    this.text, {
    this.isHeadline = false,
    this.fontColor,
    this.fontSize,
    this.fontFamily,
    this.lineSpacing,
    this.letterSpacing,
    this.textAlign,
  }) : type = "text",
       image = null,
       imageUrl = null,
       imageWidth = null,
       previousText = text;

  PageBlock.image(this.image)
    : type = "image",
      text = null,
      imageUrl = null,
      isHeadline = false,
      imageWidth = 200,
      imagePosition = const Offset(0, 0),
      previousText = null;

  PageBlock.networkImage(this.imageUrl)
    : type = "image",
      text = null,
      isHeadline = false,
      image = null,
      imageWidth = 200,
      imagePosition = const Offset(0, 0),
      previousText = null;
}

class PageData {
  double fontSize;
  String fontFamily;
  int fontColor;
  double lineSpacing;
  double letterSpacing;
  double pageMargin;
  TextAlign textAlign;

  List<PageBlock> blocks;

  PageData({
    required this.fontSize,
    required this.fontFamily,
    required this.fontColor,
    this.lineSpacing = 1.4,
    this.letterSpacing = 0.0,
    this.pageMargin = 50.0,
    this.textAlign = TextAlign.left,
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
  String? _draftId;

  // previously a fixed constant – use a getter so the limit updates
  // with the screen size/keyboard adjustments.
  double get _pageHeightLimit => MediaQuery.of(context).size.height * 0.65;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  int? _focusedBlockIndex;

  // State variables consolidated at top
  List<PageData> _pages = [
    PageData(fontSize: 22, fontFamily: "Roboto", fontColor: 0xFF000000),
  ];
  int _currentPage = 0;
  final PageController _pageController = PageController();

  List<List<PageData>> _historyStack = [];
  int _historyIndex = -1;
  bool _isUndoRedoOp = false;
  Timer? _debounceTimer;

  // Active styles for NEW blocks
  int _activeColor = 0xFF000000;
  bool _activeHeadline = false;

  final List<String> _fontFamilies = [
    "Roboto",
    "Lora",
    "Playfair Display",
    "Mukta Malar",
    "Hind Madurai",
    "Pavanam",
    "Arima",
    "Kavivanar",
    "Catamaran",
    "Baloo 2",
    "Tiro Tamil",
    "Roboto",
    "Lora",
    "Inter",
    "Merienda",
    "Lobster",
  ];

  final List<int> _fontColors = [
    0xFF000000, // Black
    0xFFF44336, // Red
    0xFF2196F3, // Blue
    0xFF4CAF50, // Green
    0xFF9C27B0, // Purple
    0xFFFF9800, // Orange
    0xFF009668, // Teal
    0xFF795548, // Brown
    0xFFB11226, // Brand Red
  ];

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveToHistory(immediate: true);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _debounceTimer?.cancel();
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    for (var node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  List<PageData> _clonePages(List<PageData> source) {
    return source.map((p) => PageData(
      fontSize: p.fontSize,
      fontFamily: p.fontFamily,
      fontColor: p.fontColor,
      lineSpacing: p.lineSpacing,
      letterSpacing: p.letterSpacing,
      pageMargin: p.pageMargin,
      textAlign: p.textAlign,
    )..blocks = p.blocks.map((b) {
      if (b.type == "text") {
        return PageBlock.text(
          b.text ?? "",
          isHeadline: b.isHeadline,
          fontSize: b.fontSize,
          fontFamily: b.fontFamily,
          fontColor: b.fontColor,
          lineSpacing: b.lineSpacing,
          letterSpacing: b.letterSpacing,
          textAlign: b.textAlign,
        );
      } else {
        var img = PageBlock.networkImage(b.imageUrl ?? "");
        img.image = b.image;
        img.imageWidth = b.imageWidth;
        img.imagePosition = b.imagePosition;
        return img;
      }
    }).toList()).toList();
  }

  void _saveToHistory({bool immediate = false}) {
    if (_isUndoRedoOp) return;

    void save() {
      if (_historyIndex >= 0 && _historyIndex < _historyStack.length - 1) {
        _historyStack = _historyStack.sublist(0, _historyIndex + 1);
      }
      _historyStack.add(_clonePages(_pages));
      _historyIndex = _historyStack.length - 1;
      
      if (_historyStack.length > 50) {
        _historyStack.removeAt(0);
        _historyIndex--;
      }
      if (mounted) setState(() {});
    }

    if (immediate) {
      _debounceTimer?.cancel();
      save();
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 600), save);
    }
  }

  void _flushHistoryIfPending() {
    if (_debounceTimer?.isActive ?? false) {
      _saveToHistory(immediate: true);
    }
  }

  void _applyStateSafety() {
    if (_currentPage >= _pages.length) {
      _currentPage = _pages.length > 0 ? _pages.length - 1 : 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentPage);
        }
      });
    }
    if (_focusedBlockIndex != null) {
      if (_currentPage < _pages.length) {
        if (_focusedBlockIndex! >= _pages[_currentPage].blocks.length) {
          _focusedBlockIndex = null;
        }
      } else {
        _focusedBlockIndex = null;
      }
    }
  }

  void _globalUndo() {
    if (_historyIndex > 0) {
      if (_debounceTimer?.isActive ?? false) {
        _debounceTimer?.cancel();
        _saveToHistory(immediate: true);
      }
      setState(() {
        _isUndoRedoOp = true;
        _historyIndex--;
        _pages = _clonePages(_historyStack[_historyIndex]);
        _applyStateSafety();
        _rebuildAllControllers();
        _isUndoRedoOp = false;
      });
    }
  }

  void _globalRedo() {
    if (_historyIndex < _historyStack.length - 1) {
      setState(() {
        _isUndoRedoOp = true;
        _historyIndex++;
        _pages = _clonePages(_historyStack[_historyIndex]);
        _applyStateSafety();
        _rebuildAllControllers();
        _isUndoRedoOp = false;
      });
    }
  }

  void _rebuildAllControllers() {
    Set<String> activeKeys = {};
    for (int p = 0; p < _pages.length; p++) {
      for (int b = 0; b < _pages[p].blocks.length; b++) {
        if (_pages[p].blocks[b].type == "text") {
          String key = "$p-$b";
          activeKeys.add(key);
          if (_controllers.containsKey(key)) {
            if (_controllers[key]!.text != _pages[p].blocks[b].text) {
              _controllers[key]!.text = _pages[p].blocks[b].text ?? "";
            }
          } else {
            final ctrl = TextEditingController(text: _pages[p].blocks[b].text ?? "");
            ctrl.addListener(() {
              if (!_isUndoRedoOp && _pages[p].blocks[b].text != ctrl.text) {
                _handleTextChange(ctrl.text, p, b);
              }
            });
            _controllers[key] = ctrl;
            _focusNodes[key] = FocusNode();
          }
        }
      }
    }

    final controllersToDispose = <TextEditingController>[];
    final nodesToDispose = <FocusNode>[];

    _controllers.removeWhere((key, ctrl) {
      if (!activeKeys.contains(key)) {
        controllersToDispose.add(ctrl);
        if (_focusNodes.containsKey(key)) {
          nodesToDispose.add(_focusNodes[key]!);
          _focusNodes.remove(key);
        }
        return true;
      }
      return false;
    });

    if (controllersToDispose.isNotEmpty || nodesToDispose.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (var c in controllersToDispose) {
          c.dispose();
        }
        for (var n in nodesToDispose) {
          n.dispose();
        }
      });
    }
  }

  void _onFocusChanged(int blockIndex, bool hasFocus) {
    if (hasFocus) {
      setState(() {
        _focusedBlockIndex = blockIndex;
      });
    }
  }

  // optionally assume an image will be added (useful when calculating before inserting)
  bool _doesTextOverflow(
    String text,
    PageData page,
    double maxWidth, {
    bool assumeImage = false,
    bool isHeadline = false,
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    TextAlign? textAlign,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: isHeadline ? 28 : (fontSize ?? page.fontSize),
          fontWeight: isHeadline ? FontWeight.w900 : FontWeight.w400,
          fontFamily: fontFamily ?? page.fontFamily,
          height: lineSpacing ?? page.lineSpacing,
          letterSpacing: isHeadline
              ? -0.5
              : (letterSpacing ?? page.letterSpacing),
        ),
      ),
      maxLines: null,
      textAlign: textAlign ?? page.textAlign,
      textDirection: TextDirection.ltr,
    );

    painter.layout(maxWidth: maxWidth);

    // consider the whole page: any image affects layout
    bool hasImage = assumeImage || page.blocks.any((b) => b.type == "image");

    // enforce line counts: 25 lines per page
    int actualLines = painter.computeLineMetrics().length;
    int allowedLines = 23;
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

    // Collect all text blocks and images from this page onwards
    List<PageBlock> originalTextBlocks = [];
    List<MapEntry<int, int>> imagePositions = []; // (pageIdx, blockIdx) pairs

    for (int p = pageIndex; p < _pages.length; p++) {
      for (int b = 0; b < _pages[p].blocks.length; b++) {
        final block = _pages[p].blocks[b];
        if (block.type == "text" && (block.text ?? "").isNotEmpty) {
          originalTextBlocks.add(
            PageBlock.text(
              block.text!,
              isHeadline: block.isHeadline,
              fontColor: block.fontColor,
              fontSize: block.fontSize,
              fontFamily: block.fontFamily,
              lineSpacing: block.lineSpacing,
              letterSpacing: block.letterSpacing,
              textAlign: block.textAlign,
            ),
          );
        } else if (block.type == "image") {
          imagePositions.add(MapEntry(p, b));
        }
      }
    }

    // Clear all text blocks from this page onwards (keep images for now)
    for (int p = pageIndex; p < _pages.length; p++) {
      _pages[p].blocks.removeWhere((b) => b.type == "text");
    }

    // Redistribute all collected blocks starting from this page
    if (originalTextBlocks.isNotEmpty) {
      _distributeBlocksToPages(pageIndex, originalTextBlocks);
    }

    // Track current keys to avoid disposing active controllers
    Set<String> activeKeys = {};
    for (int p = pageIndex; p < _pages.length; p++) {
      for (int b = 0; b < _pages[p].blocks.length; b++) {
        if (_pages[p].blocks[b].type == "text") {
          activeKeys.add("$p-$b");
        }
      }
    }

    // Update or create controllers, keeping track of what we use
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

    // Cleanup orphaned controllers
    final controllersToDispose = <TextEditingController>[];
    final nodesToDispose = <FocusNode>[];

    _controllers.removeWhere((key, ctrl) {
      if (!activeKeys.contains(key)) {
        controllersToDispose.add(ctrl);
        if (_focusNodes.containsKey(key)) {
          nodesToDispose.add(_focusNodes[key]!);
          _focusNodes.remove(key);
        }
        return true;
      }
      return false;
    });

    if (controllersToDispose.isNotEmpty || nodesToDispose.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (var c in controllersToDispose) {
          c.dispose();
        }
        for (var n in nodesToDispose) {
          n.dispose();
        }
      });
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

  /// distribute blocks starting at [startPage] across pages, creating
  /// new pages as needed while preserving text block attributes.
  void _distributeBlocksToPages(
    int startPage,
    List<PageBlock> blocksToDistribute,
  ) {
    double maxWidth =
        MediaQuery.of(context).size.width - (_pages[0].pageMargin * 2);
    int pageIdx = startPage;

    for (int i = 0; i < blocksToDistribute.length; i++) {
      var srcBlock = blocksToDistribute[i];
      String remaining = srcBlock.text ?? "";

      while (remaining.isNotEmpty) {
        // Ensure we skip pages that already contain an image
        while (pageIdx < _pages.length &&
            _pages[pageIdx].blocks.any((b) => b.type == "image")) {
          pageIdx++;
        }

        // ensure page exists
        if (pageIdx >= _pages.length) {
          _pages.add(
            PageData(
              fontSize: _pages[0].fontSize,
              fontFamily: _pages[0].fontFamily,
              fontColor: _pages[0].fontColor,
            )..blocks.clear(),
          );
        }

        PageData page = _pages[pageIdx];

        // If this is a new page (not the starting page), clear empty blocks
        if (pageIdx > startPage) {
          page.blocks.removeWhere(
            (b) => b.type == "text" && (b.text ?? "").trim().isEmpty,
          );
        }

        // find or create a text block at end WITH SAME ATTRIBUTES
        PageBlock? lastBlock;
        if (page.blocks.isNotEmpty && page.blocks.last.type == "text") {
          if (page.blocks.last.isHeadline == srcBlock.isHeadline &&
              page.blocks.last.fontColor == srcBlock.fontColor &&
              page.blocks.last.fontSize == srcBlock.fontSize &&
              page.blocks.last.fontFamily == srcBlock.fontFamily &&
              page.blocks.last.lineSpacing == srcBlock.lineSpacing &&
              page.blocks.last.letterSpacing == srcBlock.letterSpacing &&
              page.blocks.last.textAlign == srcBlock.textAlign) {
            lastBlock = page.blocks.last;
          }
        }

        if (lastBlock == null) {
          lastBlock = PageBlock.text(
            "",
            isHeadline: srcBlock.isHeadline,
            fontColor: srcBlock.fontColor,
            fontSize: srcBlock.fontSize,
            fontFamily: srcBlock.fontFamily,
            lineSpacing: srcBlock.lineSpacing,
            letterSpacing: srcBlock.letterSpacing,
            textAlign: srcBlock.textAlign,
          );
          page.blocks.add(lastBlock);
        }

        String existing = lastBlock.text ?? "";

        // If we are appending a different block that happened to share styles,
        // add a newline if the existing block isn't empty, to respect their original separation
        String candidate;
        if (existing.isNotEmpty &&
            !remaining.startsWith("\n") &&
            !existing.endsWith("\n")) {
          candidate = existing + "\n" + remaining;
        } else {
          candidate = existing + remaining;
        }

        if (!_doesTextOverflow(
          candidate,
          page,
          maxWidth,
          isHeadline: srcBlock.isHeadline,
        )) {
          // whole remainder fits on this page
          lastBlock.text = candidate;
          remaining = "";
        } else {
          // need to split; binary search for largest prefix that fits
          int low = 0, high = remaining.length;
          while (low < high) {
            int mid = (low + high + 1) ~/ 2;

            String tempCandidate;
            if (existing.isNotEmpty &&
                !remaining.startsWith("\n") &&
                !existing.endsWith("\n")) {
              tempCandidate = existing + "\n" + remaining.substring(0, mid);
            } else {
              tempCandidate = existing + remaining.substring(0, mid);
            }

            if (_doesTextOverflow(
              tempCandidate,
              page,
              maxWidth,
              isHeadline: srcBlock.isHeadline,
              fontSize: srcBlock.fontSize,
              fontFamily: srcBlock.fontFamily,
              lineSpacing: srcBlock.lineSpacing,
              letterSpacing: srcBlock.letterSpacing,
              textAlign: srcBlock.textAlign,
            )) {
              high = mid - 1;
            } else {
              low = mid;
            }
          }
          if (low == 0) {
            // If even one character doesn't fit, move to next page
            pageIdx++;
            continue;
          }

          String fitPart = remaining.substring(0, low);

          // Improve word wrapping: avoid breaking words if possible to prevent single-letter lines
          if (low < remaining.length &&
              !remaining[low].contains(RegExp(r'\s')) &&
              !remaining[low - 1].contains(RegExp(r'\s'))) {
            int lastSpace = remaining.substring(0, low).lastIndexOf(' ');
            if (lastSpace > 0) {
              low = lastSpace;
              fitPart = remaining.substring(0, low);
            }
          }

          if (existing.isNotEmpty &&
              !remaining.startsWith("\n") &&
              !existing.endsWith("\n")) {
            lastBlock.text = existing + "\n" + fitPart;
          } else {
            lastBlock.text = existing + fitPart;
          }

          remaining = remaining.substring(low).trimLeft();
          pageIdx++;
        }
      }
    }
  }

  void _handleTextChange(String value, int pageIndex, int blockIndex) {
    if (_isUndoRedoOp) return;

    setState(() {
      // Update text without truncating lines
      _pages[pageIndex].blocks[blockIndex].text = value;
      _pages[pageIndex].blocks[blockIndex].previousText = value;

      _saveToHistory(immediate: false);
    });

    int oldPageCount = _pages.length;
    final page = _pages[pageIndex];
    double maxWidth = MediaQuery.of(context).size.width - (page.pageMargin * 2);

    if (_doesTextOverflow(value, page, maxWidth)) {
      _rebalancePagesFromIndex(pageIndex);

      // Check if we need to move focus to the next page
      // This happens if a new page was created OR if content moved to the next page
      String newBlockText = _pages[pageIndex].blocks[blockIndex].text ?? "";
      bool contentMoved = newBlockText.length < value.length;

      if (_pages.length > oldPageCount || contentMoved) {
        int newPageIndex = (_pages.length > oldPageCount)
            ? _pages.length - 1
            : pageIndex + 1;

        // Ensure target page is valid
        if (newPageIndex >= _pages.length) return;

        setState(() {
          _currentPage = newPageIndex;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pageController.jumpToPage(newPageIndex);
        });

        Future.delayed(const Duration(milliseconds: 100), () {
          // Find first text block in next page
          int targetBlockIndex = 0;
          for (int b = 0; b < _pages[newPageIndex].blocks.length; b++) {
            if (_pages[newPageIndex].blocks[b].type == "text") {
              targetBlockIndex = b;
              break;
            }
          }

          String key = "$newPageIndex-$targetBlockIndex";

          if (!_controllers.containsKey(key)) {
            _controllers[key] = TextEditingController(
              text: _pages[newPageIndex].blocks[targetBlockIndex].text ?? "",
            );
          }

          if (!_focusNodes.containsKey(key)) {
            _focusNodes[key] = FocusNode();
          }

          FocusScope.of(context).requestFocus(_focusNodes[key]);

          // Place cursor at the end
          final ctrl = _controllers[key]!;
          ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
        });
      }
    } else {
      _pullContentUpIfSpace(pageIndex);
    }

    while (_pages.length > 1 &&
        _pages.last.blocks.every(
          (b) => b.type != "text" || (b.text ?? "").trim().isEmpty,
        ) &&
        !_pages.last.blocks.any((b) => b.type == "image")) {
      _pages.removeLast();
      if (_currentPage >= _pages.length) {
        _currentPage = _pages.length - 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentPage);
          }
        });
      }
    }
  }

  /// Pull content from next page if current page has space
  void _pullContentUpIfSpace(int pageIndex) {
    if (pageIndex >= _pages.length - 1) return; // No next page

    var currentPage = _pages[pageIndex];
    // Rule: Skip if current page is an image page
    if (currentPage.blocks.any((b) => b.type == "image")) return;

    double maxWidth =
        MediaQuery.of(context).size.width - (currentPage.pageMargin * 2);
    var nextPage = _pages[pageIndex + 1];

    // Rule: Skip if next page is an image page
    if (nextPage.blocks.any((b) => b.type == "image")) return;

    // Calculate current page usage
    String currentText = "";
    for (var b in currentPage.blocks) {
      if (b.type == "text") currentText += "${b.text ?? ""}\n";
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
          String testText = "$currentText\n${blockToMove.text ?? ""}";

          if (!_doesTextOverflow(testText, currentPage, maxWidth)) {
            // It fits! Move the block while preserving styles
            currentPage.blocks.add(
              PageBlock.text(
                blockToMove.text ?? "",
                isHeadline: blockToMove.isHeadline,
                fontColor: blockToMove.fontColor,
                fontSize: blockToMove.fontSize,
                fontFamily: blockToMove.fontFamily,
                lineSpacing: blockToMove.lineSpacing,
                letterSpacing: blockToMove.letterSpacing,
                textAlign: blockToMove.textAlign,
              ),
            );
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

  void _loadDraftContent(String content) {
    try {
      final decoded = jsonDecode(content);

      List<dynamic> pagesData = [];

      // handle both formats
      if (decoded is Map && decoded.containsKey("pages")) {
        pagesData = decoded["pages"];
      } else if (decoded is List) {
        pagesData = decoded;
      }

      _pages = [];

      for (var page in pagesData) {
        PageData pageData = PageData(
          fontSize: (page['fontSize'] ?? 22).toDouble(),
          fontFamily: page['fontFamily'] ?? "Roboto",
          fontColor: page['fontColor'] ?? Colors.black.value,
          lineSpacing: (page['lineSpacing'] ?? 1.4).toDouble(),
          letterSpacing: (page['letterSpacing'] ?? 0.0).toDouble(),
          pageMargin: (page['pageMargin'] ?? 50.0).toDouble(),
          textAlign: TextAlign.values[page['textAlign'] ?? 0],
        );

        pageData.blocks.clear();

        if (page['blocks'] != null) {
          for (var block in page['blocks']) {
            if (block['type'] == "text") {
              pageData.blocks.add(
                PageBlock.text(
                  block['text'] ?? "",
                  isHeadline: block['isHeadline'] ?? false,
                  fontSize: (block['fontSize'] as num?)?.toDouble(),
                  fontFamily: block['fontFamily'] as String?,
                  fontColor: (block['fontColor'] as num?)?.toInt(),
                  lineSpacing: (block['lineSpacing'] as num?)?.toDouble(),
                  letterSpacing: (block['letterSpacing'] as num?)?.toDouble(),
                  textAlign: block['textAlign'] != null
                      ? TextAlign.values[(block['textAlign'] as num).toInt()]
                      : null,
                ),
              );
            }

            if (block['type'] == "image") {
              final imageName = block['image'];

              print("IMAGE RAW: $imageName"); // DEBUG

              if (imageName == null || imageName.toString().isEmpty) {
                print("❌ Image missing in draft");
                continue;
              }

              String finalUrl = imageName.toString();

              // ✅ If not full URL → convert
              if (!finalUrl.startsWith("http")) {
                if (finalUrl.contains("uploads/")) {
                  finalUrl = "https://bigiluu.com/$finalUrl";
                } else {
                  finalUrl =
                      "https://bigiluu.com/uploads/page_images/$finalUrl";
                }
              }

              print("✅ FINAL URL: $finalUrl");

              final imgBlock = PageBlock.networkImage(finalUrl);

              imgBlock.imageWidth = (block['imageWidth'] ?? 200).toDouble();

              imgBlock.imagePosition = Offset(
                (block['imagePosX'] ?? 0).toDouble(),
                (block['imagePosY'] ?? 0).toDouble(),
              );

              pageData.blocks.add(imgBlock);
            }
          }
        }

        _pages.add(pageData);
      }

      if (_pages.isEmpty) {
        _pages.add(
          PageData(
            fontSize: 22,
            fontFamily: "Roboto",
            fontColor: Colors.black.value,
            lineSpacing: 1.4,
            letterSpacing: 0.0,
            pageMargin: 50.0,
            textAlign: TextAlign.left,
          ),
        );
      }

      setState(() {
        _currentPage = 0;
      });
    } catch (e) {
      print("❌ Draft load crash: $e");

      // prevent crash
      setState(() {
        _pages = [
          PageData(
            fontSize: 22,
            fontFamily: "Roboto",
            fontColor: Colors.black.value,
            lineSpacing: 1.4,
            letterSpacing: 0.0,
            pageMargin: 50.0,
            textAlign: TextAlign.left,
          ),
        ];
        _currentPage = 0;
      });
    }
  }

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");

    final uri = Uri.parse("https://bigiluu.com/api/draft/saveDraft");

    var request = http.MultipartRequest("POST", uri);

    request.fields["user_id"] = userId ?? "";

    if (_draftId != null) {
      request.fields["draft_id"] = _draftId!;
    }

    List<Map<String, dynamic>> pagesJson = [];

    for (var page in _pages) {
      List<Map<String, dynamic>> blocksJson = [];

      for (var block in page.blocks) {
        String? imageName;

        if (block.type == "image") {
          // ✅ CASE 1: NEW IMAGE (picked from gallery)
          if (block.image != null) {
            print("📤 Uploading NEW image: ${block.image!.path}");

            request.files.add(
              await http.MultipartFile.fromPath(
                "page_images", // 🔥 must match backend
                block.image!.path,
              ),
            );

            imageName = null; // backend will assign filename
          }
          // ✅ CASE 2: OLD IMAGE (already from server)
          else if (block.imageUrl != null) {
            print("🌐 Using EXISTING image: ${block.imageUrl}");

            imageName = block.imageUrl; // keep existing
          }
        }

        blocksJson.add({
          "type": block.type,
          "text": block.text,
          "image": imageName,
          "imageWidth": block.imageWidth,
          "imagePosX": block.imagePosition?.dx,
          "imagePosY": block.imagePosition?.dy,
          "isHeadline": block.isHeadline,
          "fontColor": block.fontColor,
          "fontSize": block.fontSize,
          "fontFamily": block.fontFamily,
          "lineSpacing": block.lineSpacing,
          "letterSpacing": block.letterSpacing,
          "textAlign": block.textAlign?.index,
        });
      }

      pagesJson.add({
        "fontSize": page.fontSize,
        "fontFamily": page.fontFamily,
        "fontColor": page.fontColor,
        "lineSpacing": page.lineSpacing,
        "letterSpacing": page.letterSpacing,
        "pageMargin": page.pageMargin,
        "textAlign": page.textAlign.index,
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
      _flushHistoryIfPending();
      setState(() {
        int targetPage = index;

        // Rule: A page can ONLY have an image OR text, not both.
        // If current page is not empty, we MUST move the image to a new page.
        bool currentPageHasContent = _pages[index].blocks.any(
          (b) =>
              b.type == "image" ||
              (b.type == "text" && (b.text ?? "").trim().isNotEmpty),
        );

        if (currentPageHasContent) {
          targetPage = index + 1;
          if (targetPage >= _pages.length) {
            _pages.add(
              PageData(
                fontSize: _pages[0].fontSize,
                fontFamily: _pages[0].fontFamily,
                fontColor: _pages[0].fontColor,
                lineSpacing: _pages[0].lineSpacing,
                letterSpacing: _pages[0].letterSpacing,
                pageMargin: _pages[0].pageMargin,
                textAlign: _pages[0].textAlign,
              ),
            );
          } else {
            // Insert a fresh page for the image
            _pages.insert(
              targetPage,
              PageData(
                fontSize: _pages[0].fontSize,
                fontFamily: _pages[0].fontFamily,
                fontColor: _pages[0].fontColor,
                lineSpacing: _pages[0].lineSpacing,
                letterSpacing: _pages[0].letterSpacing,
                pageMargin: _pages[0].pageMargin,
                textAlign: _pages[0].textAlign,
              ),
            );
          }
          _pages[targetPage].blocks.clear();
        } else {
          // Current page is empty, reuse it
          _pages[targetPage].blocks.clear();
        }

        _pages[targetPage].blocks.add(PageBlock.image(File(image.path)));

        _currentPage = targetPage;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pageController.jumpToPage(targetPage);
        });
      });
      _saveToHistory(immediate: true);
    }
  }

  void _removeImageBlock(int pageIndex, int blockIndex) {
    _flushHistoryIfPending();
    setState(() {
      final blocks = _pages[pageIndex].blocks;
      blocks.removeAt(blockIndex);

      // If page is now empty, add a default text block
      if (blocks.isEmpty) {
        blocks.add(PageBlock.text(""));
      }

      // if removing left two adjacent text blocks, merge them
      for (int i = 0; i < blocks.length - 1; i++) {
        if (blocks[i].type == "text" && blocks[i + 1].type == "text") {
          blocks[i].text =
              '${blocks[i].text ?? ""}\n${blocks[i + 1].text ?? ""}';
          blocks.removeAt(i + 1);
          break;
        }
      }

      // Trigger rebalance to pull content from next pages into this newly freed space
      _rebalancePagesFromIndex(pageIndex);
    });
    _saveToHistory(immediate: true);
  }

  void _deleteCurrentPage() {
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("At least one page is required")),
      );
      return;
    }

    _flushHistoryIfPending();

    int pageToDelete = _currentPage; // ✅ lock the correct page index

    setState(() {
      _pages.removeAt(pageToDelete);

      // move cursor safely
      if (_currentPage >= _pages.length) {
        _currentPage = _pages.length - 1;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(_currentPage);
      });

      // update controllers safely
      Map<String, TextEditingController> newControllers = {};
      Map<String, FocusNode> newFocusNodes = {};

      for (int p = 0; p < _pages.length; p++) {
        for (int b = 0; b < _pages[p].blocks.length; b++) {
          if (_pages[p].blocks[b].type == "text") {
            String oldKey = "${p >= pageToDelete ? p + 1 : p}-$b";
            String newKey = "$p-$b";

            if (_controllers.containsKey(oldKey)) {
              newControllers[newKey] = _controllers[oldKey]!;
            }

            if (_focusNodes.containsKey(oldKey)) {
              newFocusNodes[newKey] = _focusNodes[oldKey]!;
            }
          }
        }
      }

      _controllers
        ..clear()
        ..addAll(newControllers);

      _focusNodes
        ..clear()
        ..addAll(newFocusNodes);
    });
    _saveToHistory(immediate: true);
  }

  void _addNewPage() {
    _flushHistoryIfPending();
    setState(() {
      final lastPage = _pages.isNotEmpty ? _pages.last : null;
      _pages.add(
        PageData(
          fontSize: lastPage?.fontSize ?? 22,
          fontFamily: lastPage?.fontFamily ?? "Roboto",
          fontColor: lastPage?.fontColor ?? Colors.black.value,
          lineSpacing: lastPage?.lineSpacing ?? 1.4,
          letterSpacing: lastPage?.letterSpacing ?? 0.0,
          pageMargin: lastPage?.pageMargin ?? 50.0,
          textAlign: lastPage?.textAlign ?? TextAlign.left,
        ),
      );
      _pageController.jumpToPage(_pages.length - 1);
      _currentPage = _pages.length - 1;
    });
    _saveToHistory(immediate: true);
  }

  void _addNewTextBlock(int pageIndex) {
    if (pageIndex >= _pages.length) return;

    // Rule: Cannot add text to a page that already has an image
    if (_pages[pageIndex].blocks.any((b) => b.type == "image")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot add text to an image page")),
      );
      return;
    }

    _flushHistoryIfPending();

    // Add a new empty text block to the current page so the user can type independently
    setState(() {
      int insertIndex = (_focusedBlockIndex ?? -1) + 1;
      if (insertIndex > 0 && insertIndex < _pages[pageIndex].blocks.length) {
        _pages[pageIndex].blocks.insert(
          insertIndex,
          PageBlock.text(
            "",
            isHeadline: _activeHeadline,
            fontColor: _activeColor,
          ),
        );
      } else {
        _pages[pageIndex].blocks.add(
          PageBlock.text(
            "",
            isHeadline: _activeHeadline,
            fontColor: _activeColor,
          ),
        );
      }
    });

    // Auto focus the new block
    Future.delayed(const Duration(milliseconds: 100), () {
      int insertIndex = (_focusedBlockIndex ?? -1) + 1;
      int newBlockIndex =
          (insertIndex > 0 && insertIndex < _pages[pageIndex].blocks.length)
          ? insertIndex
          : _pages[pageIndex].blocks.length - 1;

      String key = "$pageIndex-$newBlockIndex";

      if (!_controllers.containsKey(key)) {
        _controllers[key] = TextEditingController(text: "");
      }
      if (!_focusNodes.containsKey(key)) {
        _focusNodes[key] = FocusNode();
      }

      FocusScope.of(context).requestFocus(_focusNodes[key]);
      _onFocusChanged(newBlockIndex, true);
    });
    _saveToHistory(immediate: true);
  }

  void _applyStyleToSelection({
    double? fontSize,
    String? fontFamily,
    int? fontColor,
    bool? isHeadline,
    double? lineSpacing,
    double? letterSpacing,
    TextAlign? textAlign,
  }) {
    if (_focusedBlockIndex == null) return;
    final pageIdx = _currentPage;
    final page = _pages[pageIdx];
    final blockIndex = _focusedBlockIndex!;
    final block = page.blocks[blockIndex];
    if (block.type != "text") return;

    final key = "$pageIdx-$blockIndex";
    final controller = _controllers[key];
    if (controller == null) return;

    _flushHistoryIfPending();

    final selection = controller.selection;
    final text = controller.text;

    // BOUNDS CHECK
    if (fontSize != null && fontSize < 12) fontSize = 12;

    // ALIGNMENT and LINE SPACING usually apply to the entire paragraph/block.
    // However, if the user HAS a selection, we respect their wish to split it.
    if (selection.isCollapsed ||
        selection.start == -1 ||
        selection.start == selection.end) {
      if (textAlign != null || lineSpacing != null) {
        setState(() {
          if (textAlign != null) block.textAlign = textAlign;
          if (lineSpacing != null) block.lineSpacing = lineSpacing;
        });
        // If ONLY alignment/spacing was changed, we don't need to do more.
        if (fontSize == null &&
            fontFamily == null &&
            fontColor == null &&
            isHeadline == null &&
            letterSpacing == null) {
          _saveToHistory(immediate: true);
          return;
        }
      }
    }

    if (selection.isCollapsed ||
        selection.start == -1 ||
        selection.start == selection.end) {
      // Apply to WHOLE block (block-level override)
      setState(() {
        if (fontSize != null) block.fontSize = fontSize;
        if (fontFamily != null) block.fontFamily = fontFamily;
        if (fontColor != null) block.fontColor = fontColor;
        if (isHeadline != null) block.isHeadline = isHeadline;
        if (lineSpacing != null) block.lineSpacing = lineSpacing;
        if (letterSpacing != null) block.letterSpacing = letterSpacing;
        if (textAlign != null) block.textAlign = textAlign;
      });
      _saveToHistory(immediate: true);
      return;
    }

    // SPLIT BLOCK
    final beforeText = text.substring(0, selection.start);
    final selectedText = text.substring(selection.start, selection.end);
    final afterText = text.substring(selection.end);

    setState(() {
      page.blocks.removeAt(blockIndex);

      int insertAt = blockIndex;

      if (beforeText.isNotEmpty) {
        page.blocks.insert(
          insertAt++,
          PageBlock.text(
            beforeText,
            isHeadline: block.isHeadline,
            fontColor: block.fontColor,
            fontSize: block.fontSize,
            fontFamily: block.fontFamily,
            lineSpacing: block.lineSpacing,
            letterSpacing: block.letterSpacing,
            textAlign: block.textAlign,
          ),
        );
      }

      final middleBlock = PageBlock.text(
        (isHeadline ?? block.isHeadline)
            ? selectedText.toUpperCase()
            : selectedText,
        isHeadline: isHeadline ?? block.isHeadline,
        fontColor: fontColor ?? block.fontColor,
        fontSize: fontSize ?? block.fontSize,
        fontFamily: fontFamily ?? block.fontFamily,
        lineSpacing: lineSpacing ?? block.lineSpacing,
        letterSpacing: letterSpacing ?? block.letterSpacing,
        textAlign: textAlign ?? block.textAlign,
      );
      final int activeBlockIndex = insertAt;
      page.blocks.insert(insertAt++, middleBlock);

      if (afterText.isNotEmpty) {
        page.blocks.insert(
          insertAt++,
          PageBlock.text(
            afterText,
            isHeadline: block.isHeadline,
            fontColor: block.fontColor,
            fontSize: block.fontSize,
            fontFamily: block.fontFamily,
            lineSpacing: block.lineSpacing,
            letterSpacing: block.letterSpacing,
            textAlign: block.textAlign,
          ),
        );
      }

      // Restore focus to the middle block
      _focusedBlockIndex = activeBlockIndex;
    });

    _rebalancePagesFromIndex(pageIdx);

    // RESTORE SELECTION & FOCUS POST-REBALANCE
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newKey = "$pageIdx-$_focusedBlockIndex";
      if (_controllers.containsKey(newKey)) {
        final ctrl = _controllers[newKey]!;
        final len = ctrl.text.length;
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: len);
        if (_focusNodes.containsKey(newKey)) {
          FocusScope.of(context).requestFocus(_focusNodes[newKey]);
        }
      }
    });
    _saveToHistory(immediate: true);
  }

  void _applyGlobalStyle({
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    TextAlign? textAlign,
    double? pageMargin,
  }) {
    _flushHistoryIfPending();
    setState(() {
      for (var p in _pages) {
        if (fontSize != null) p.fontSize = fontSize;
        if (fontFamily != null) p.fontFamily = fontFamily;
        if (lineSpacing != null) p.lineSpacing = lineSpacing;
        if (letterSpacing != null) p.letterSpacing = letterSpacing;
        if (textAlign != null) p.textAlign = textAlign;
        if (pageMargin != null) p.pageMargin = pageMargin;

        for (var b in p.blocks) {
          if (b.type == "text") {
            if (fontSize != null) b.fontSize = fontSize;
            if (fontFamily != null) b.fontFamily = fontFamily;
            if (lineSpacing != null) b.lineSpacing = lineSpacing;
            if (letterSpacing != null) b.letterSpacing = letterSpacing;
            if (textAlign != null) b.textAlign = textAlign;
          }
        }
      }
    });

    if (fontSize != null ||
        fontFamily != null ||
        lineSpacing != null ||
        letterSpacing != null ||
        pageMargin != null) {
      _rebalancePagesFromIndex(0);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusedBlockIndex != null && _currentPage < _pages.length) {
        final newKey = "$_currentPage-$_focusedBlockIndex";
        if (_focusNodes.containsKey(newKey)) {
          FocusScope.of(context).requestFocus(_focusNodes[newKey]);
        }
      }
    });
    _saveToHistory(immediate: true);
  }

  void _applyStyleSmartly({
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    TextAlign? textAlign,
  }) {
    bool hasSelection = false;
    if (_focusedBlockIndex != null) {
      final key = "$_currentPage-$_focusedBlockIndex";
      final ctrl = _controllers[key];
      if (ctrl != null &&
          ctrl.selection.isValid &&
          !ctrl.selection.isCollapsed &&
          ctrl.selection.start != -1) {
        hasSelection = true;
      }
    }

    if (hasSelection) {
      _applyStyleToSelection(
        fontSize: fontSize,
        fontFamily: fontFamily,
        lineSpacing: lineSpacing,
        letterSpacing: letterSpacing,
        textAlign: textAlign,
      );
    } else {
      _applyGlobalStyle(
        fontSize: fontSize,
        fontFamily: fontFamily,
        lineSpacing: lineSpacing,
        letterSpacing: letterSpacing,
        textAlign: textAlign,
      );
    }
  }

  // FIXED BUILD METHOD START
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
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.05),
          automaticallyImplyLeading: false,
          toolbarHeight: 70,
          title: Row(
            children: [
              Image.asset(
                "assets/images/bigilu_logo21.png",
                height: 50,
                fit: BoxFit.contain,
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await saveDraft();
                  Navigator.pop(context, true);
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB11226),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: const Color(0xFFB11226).withOpacity(0.2),
                    ),
                  ),
                ),
                child: const Text(
                  "Draft",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB11226),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Continue",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.05,
                  vertical: 20,
                ),
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (index) {
                        setState(() => _currentPage = index);
                      },
                      itemBuilder: (context, index) {
                        return Center(
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFDFBF7,
                              ), // Premium cream paper
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Stack(
                                children: [
                                  // Spine Binding Effect
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: 32,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Colors.black.withOpacity(0.12),
                                            Colors.black.withOpacity(0.04),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Paper Texture Overlay
                                  Positioned.fill(
                                    child: Opacity(
                                      opacity: 0.02,
                                      child: Image.network(
                                        "https://www.transparenttextures.com/patterns/paper-fibers.png",
                                        repeat: ImageRepeat.repeat,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox(),
                                      ),
                                    ),
                                  ),

                                  // Content Area
                                  Container(
                                    height:
                                        MediaQuery.of(context).size.height *
                                        0.65,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: _pages[index].pageMargin,
                                      vertical: 40,
                                    ),
                                    child: SingleChildScrollView(
                                      physics: const BouncingScrollPhysics(),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ..._pages[index].blocks.asMap().entries.map((
                                            entry,
                                          ) {
                                            final blockIndex = entry.key;
                                            final block = entry.value;

                                            if (block.type == "text") {
                                              String key = "$index-$blockIndex";

                                              if (!_controllers.containsKey(key)) {
                                                final ctrl = TextEditingController(text: block.text ?? "");
                                                ctrl.addListener(() {
                                                  if (!_isUndoRedoOp && _pages[index].blocks[blockIndex].text != ctrl.text) {
                                                    _handleTextChange(ctrl.text, index, blockIndex);
                                                  }
                                                });
                                                _controllers[key] = ctrl;
                                              }

                                              if (!_focusNodes.containsKey(key)) {
                                                _focusNodes[key] = FocusNode();
                                              }

                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 4,
                                                    ),
                                                child: TextField(
                                                  controller: _controllers[key],
                                                  focusNode: _focusNodes[key],
                                                  onTap: () {
                                                    _onFocusChanged(
                                                      blockIndex,
                                                      true,
                                                    );
                                                  },
                                                  keyboardType:
                                                      TextInputType.multiline,
                                                  textCapitalization:
                                                      block.isHeadline
                                                      ? TextCapitalization
                                                            .characters
                                                      : TextCapitalization
                                                            .sentences,
                                                  textInputAction:
                                                      TextInputAction.newline,
                                                  maxLines: null,
                                                  onChanged: (value) {
                                                    _handleTextChange(
                                                      value,
                                                      index,
                                                      blockIndex,
                                                    );
                                                  },
                                                  textAlign:
                                                      block.textAlign ??
                                                      _pages[index].textAlign,
                                                  style: GoogleFonts.getFont(
                                                    block.fontFamily ??
                                                        _pages[index]
                                                            .fontFamily,
                                                    fontSize: block.isHeadline
                                                        ? 28
                                                        : (block.fontSize ??
                                                              _pages[index]
                                                                  .fontSize),
                                                    fontWeight: block.isHeadline
                                                        ? FontWeight.w900
                                                        : FontWeight.w400,
                                                    color: Color(
                                                      block.fontColor ??
                                                          _pages[index]
                                                              .fontColor,
                                                    ),
                                                    height:
                                                        block.lineSpacing ??
                                                        _pages[index]
                                                            .lineSpacing,
                                                    letterSpacing:
                                                        block.isHeadline
                                                        ? -0.5
                                                        : (block.letterSpacing ??
                                                              _pages[index]
                                                                  .letterSpacing),
                                                    backgroundColor: null,
                                                  ),
                                                  decoration: InputDecoration(
                                                    hintText: blockIndex == 0
                                                        ? "Share your story..."
                                                        : null,
                                                    hintStyle: TextStyle(
                                                      color:
                                                          Colors.grey.shade400,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
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
                                                  width: double.infinity,
                                                  fit: BoxFit.contain,
                                                );
                                              } else if (block.imageUrl !=
                                                      null &&
                                                  block.imageUrl!.isNotEmpty) {
                                                imageWidget = ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: Image.network(
                                                    block.imageUrl!,
                                                    width: double.infinity,
                                                    height:
                                                        200, // 🔥 ADD FIXED HEIGHT
                                                    fit: BoxFit.cover,
                                                    loadingBuilder:
                                                        (
                                                          context,
                                                          child,
                                                          progress,
                                                        ) {
                                                          if (progress == null)
                                                            return child;
                                                          return const Center(
                                                            child:
                                                                CircularProgressIndicator(),
                                                          );
                                                        },
                                                    errorBuilder: (c, e, s) {
                                                      print(
                                                        "❌ IMAGE LOAD ERROR: $e",
                                                      );
                                                      return const Icon(
                                                        Icons.broken_image,
                                                        size: 50,
                                                      );
                                                    },
                                                  ),
                                                );
                                              } else {
                                                return const SizedBox();
                                              }
                                              return Container(
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 16,
                                                    ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.12),
                                                      blurRadius: 10,
                                                      offset: const Offset(
                                                        0,
                                                        5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  child: Stack(
                                                    alignment:
                                                        Alignment.topRight,
                                                    children: [
                                                      imageWidget,
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              8.0,
                                                            ),
                                                        child: CircleAvatar(
                                                          backgroundColor:
                                                              Colors.white,
                                                          radius: 18,
                                                          child: IconButton(
                                                            icon: const Icon(
                                                              Icons
                                                                  .close_rounded,
                                                              color: Color(
                                                                0xFFB11226,
                                                              ),
                                                              size: 18,
                                                            ),
                                                            onPressed: () =>
                                                                _removeImageBlock(
                                                                  index,
                                                                  blockIndex,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
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
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Floating Page Indicator
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            _showPagePicker();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(204),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(51),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              "PAGE ${_currentPage + 1} / ${_pages.length}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Actions
                    Positioned(
                      left: 0,
                      bottom: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          FloatingActionButton.small(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFB11226),
                            elevation: 4,
                            heroTag: "deletePage",
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  title: const Text("Delete Page?"),
                                  content: const Text(
                                    "This action cannot be undone and will remove all content on this page.",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Keep it"),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _deleteCurrentPage();
                                      },
                                      child: const Text(
                                        "Delete",
                                        style: TextStyle(
                                          color: Color(0xFFB11226),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: const Icon(Icons.delete_outline_rounded),
                          ),
                          FloatingActionButton(
                            backgroundColor: const Color(0xFFB11226),
                            elevation: 4,
                            onPressed: _addNewPage,
                            child: const Icon(
                              Icons.add_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                          FloatingActionButton.small(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF00966F),
                            elevation: 4,
                            heroTag: "addImage",
                            onPressed: () => _pickImageForPage(_currentPage),
                            child: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                          ),
                          FloatingActionButton.small(
                            backgroundColor:
                                _pages[_currentPage].blocks.any(
                                  (b) => b.type == "image",
                                )
                                ? Colors.grey.shade100
                                : Colors.white,
                            foregroundColor:
                                _pages[_currentPage].blocks.any(
                                  (b) => b.type == "image",
                                )
                                ? Colors.grey.shade400
                                : const Color(0xFF2196F3),
                            elevation: 4,
                            heroTag: "addText",
                            onPressed: () => _addNewTextBlock(_currentPage),
                            child: const Icon(Icons.short_text_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom Toolbar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildToolbarButton(
                    context,
                    Icons.undo_rounded,
                    "Undo",
                    () {
                      HapticFeedback.lightImpact();
                      _globalUndo();
                    },
                    disabled: _historyIndex <= 0,
                  ),
                  _buildToolbarButton(
                    context,
                    Icons.text_format_rounded,
                    "Text Styles",
                    () {
                      HapticFeedback.lightImpact();
                      _showStylePicker();
                    },
                  ),
                  _buildToolbarButton(
                    context,
                    Icons.redo_rounded,
                    "Redo",
                    () {
                      HapticFeedback.lightImpact();
                      _globalRedo();
                    },
                    disabled: _historyIndex >= _historyStack.length - 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isActive = false,
    bool disabled = false,
  }) {
    final Color color = disabled 
        ? Colors.grey.withOpacity(0.3)
        : (isActive ? const Color(0xFFB11226) : Colors.grey.shade700);

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFB11226).withOpacity(0.08) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              "Go to Page",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final isCurrent = index == _currentPage;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.fastOutSlowIn,
                      );
                    },
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFFB11226)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isCurrent
                              ? const Color(0xFFB11226)
                              : Colors.grey.shade200,
                          width: 1.5,
                        ),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFB11226).withAlpha(60),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          "${index + 1}",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isCurrent ? Colors.white : Colors.black87,
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
    );
  }

  void _showStylePicker() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (_currentPage >= _pages.length) return const SizedBox();
            final page = _pages[_currentPage];
            final focusedBlock =
                (_focusedBlockIndex != null &&
                    _focusedBlockIndex! < page.blocks.length &&
                    page.blocks[_focusedBlockIndex!].type == "text")
                ? page.blocks[_focusedBlockIndex!]
                : null;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFFF9F9F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "DISPLAYS",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.grey.shade500,
                            letterSpacing: 1.2,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _applyGlobalStyle(
                              fontSize: 22,
                              lineSpacing: 1.4,
                              letterSpacing: 0.0,
                              fontFamily: "Mukta Malar",
                              textAlign: TextAlign.left,
                              pageMargin: 50.0,
                            );
                            setModalState(() {});
                          },
                          child: const Text(
                            "RESET",
                            style: TextStyle(
                              color: Color(0xFFB11226),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        // --- FONT SIZE ---
                        const SizedBox(height: 16),
                        _buildSectionHeaderLabel("FONT SIZE"),
                        const SizedBox(height: 16),
                        _buildStepper(
                          value:
                              "${(focusedBlock?.fontSize ?? page.fontSize).toInt()} px",
                          onDecrement: () {
                            if (page.fontSize > 16) {
                              _applyStyleSmartly(
                                fontSize:
                                    (focusedBlock?.fontSize ?? page.fontSize) -
                                    1,
                              );
                              setModalState(() {});
                            }
                          },
                          onIncrement: () {
                            if (page.fontSize < 48) {
                              _applyStyleSmartly(
                                fontSize:
                                    (focusedBlock?.fontSize ?? page.fontSize) +
                                    1,
                              );
                              setModalState(() {});
                            }
                          },
                        ),

                        const SizedBox(height: 32),

                        // --- FONT FAMILY ---
                        _buildSectionHeaderLabel("FONT FAMILY"),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 54,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _fontFamilies.length,
                            itemBuilder: (context, idx) {
                              final font = _fontFamilies[idx];
                              final isSelected = (focusedBlock != null)
                                  ? (focusedBlock.fontFamily ??
                                            page.fontFamily) ==
                                        font
                                  : page.fontFamily == font;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _applyStyleSmartly(fontFamily: font);
                                  setModalState(() {});
                                },
                                child: Container(
                                  height: 46,
                                  width: 120, // Enough for Tamil font names
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.05,
                                              ),
                                              blurRadius: 10,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    font,
                                    style: GoogleFonts.getFont(
                                      font,
                                      fontWeight: isSelected
                                          ? FontWeight.w900
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 32),

                        // --- TYPOGRAPHY ---
                        _buildSectionHeaderLabel("TYPOGRAPHY"),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTypographyStepper(
                                label: "LINE SPACING",
                                value:
                                    (focusedBlock?.lineSpacing ??
                                            page.lineSpacing)
                                        .toStringAsFixed(1),
                                onDecrement: () {
                                  if (page.lineSpacing > 1.0) {
                                    _applyStyleSmartly(
                                      lineSpacing:
                                          (focusedBlock?.lineSpacing ??
                                              page.lineSpacing) -
                                          0.1,
                                    );
                                    setModalState(() {});
                                  }
                                },
                                onIncrement: () {
                                  if (page.lineSpacing < 3.0) {
                                    _applyStyleSmartly(
                                      lineSpacing:
                                          (focusedBlock?.lineSpacing ??
                                              page.lineSpacing) +
                                          0.1,
                                    );
                                    setModalState(() {});
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTypographyStepper(
                                label: "LETTERING",
                                value:
                                    (focusedBlock?.letterSpacing ??
                                            page.letterSpacing)
                                        .toStringAsFixed(1),
                                onDecrement: () {
                                  if (page.letterSpacing > -2.0) {
                                    _applyStyleSmartly(
                                      letterSpacing:
                                          (focusedBlock?.letterSpacing ??
                                              page.letterSpacing) -
                                          0.1,
                                    );
                                    setModalState(() {});
                                  }
                                },
                                onIncrement: () {
                                  if (page.letterSpacing < 5.0) {
                                    _applyStyleSmartly(
                                      letterSpacing:
                                          (focusedBlock?.letterSpacing ??
                                              page.letterSpacing) +
                                          0.1,
                                    );
                                    setModalState(() {});
                                  }
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeaderLabel("ALIGNMENT"),
                                  const SizedBox(height: 12),
                                  Container(
                                    height: 54,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      children: [
                                        _buildAlignButton(
                                          TextAlign.left,
                                          focusedBlock?.textAlign ??
                                              page.textAlign,
                                          (val) {
                                            _applyStyleSmartly(textAlign: val);
                                            setModalState(() {});
                                          },
                                          Icons.format_align_left_rounded,
                                        ),
                                        _buildAlignButton(
                                          TextAlign.center,
                                          focusedBlock?.textAlign ??
                                              page.textAlign,
                                          (val) {
                                            _applyStyleSmartly(textAlign: val);
                                            setModalState(() {});
                                          },
                                          Icons.format_align_center_rounded,
                                        ),
                                        _buildAlignButton(
                                          TextAlign.right,
                                          focusedBlock?.textAlign ??
                                              page.textAlign,
                                          (val) {
                                            _applyStyleSmartly(textAlign: val);
                                            setModalState(() {});
                                          },
                                          Icons.format_align_right_rounded,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTypographyStepper(
                                label: "PAGE MARGIN",
                                value: page.pageMargin.toInt().toString(),
                                onDecrement: () {
                                  if (page.pageMargin > 10) {
                                    _applyGlobalStyle(
                                      pageMargin: page.pageMargin - 5,
                                    );
                                    setModalState(() {});
                                  }
                                },
                                onIncrement: () {
                                  if (page.pageMargin < 100) {
                                    _applyGlobalStyle(
                                      pageMargin: page.pageMargin + 5,
                                    );
                                    setModalState(() {});
                                  }
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // --- WRITING SPECIFIC: BLOCK STYLES ---
                        _buildSectionHeaderLabel("BLOCK STYLE"),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildBlockStyleButton(
                              "Headline",
                              Icons.title_rounded,
                              focusedBlock != null
                                  ? focusedBlock.isHeadline
                                  : _activeHeadline,
                              () {
                                HapticFeedback.mediumImpact();
                                if (focusedBlock != null) {
                                  _applyStyleToSelection(
                                    isHeadline: !focusedBlock.isHeadline,
                                  );
                                  setModalState(() {});
                                } else {
                                  setState(
                                    () => _activeHeadline = !_activeHeadline,
                                  );
                                  setModalState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                        if (focusedBlock == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              "Tap on text to enable block styles",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),

                        const SizedBox(height: 24),
                        _buildSectionHeaderLabel("TEXT COLOR"),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _fontColors.map((colorValue) {
                            final isSelected =
                                (focusedBlock != null &&
                                    focusedBlock.fontColor != null)
                                ? focusedBlock.fontColor == colorValue
                                : _activeColor == colorValue;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _activeColor = colorValue;

                                  if (focusedBlock != null) {
                                    _applyStyleToSelection(
                                      fontColor: colorValue,
                                    );
                                  }
                                });
                                setModalState(() {});
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Color(colorValue),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFFB11226)
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFB11226,
                                            ).withOpacity(0.4),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 18,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 60),
                      ],
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

  Widget _buildSectionHeaderLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: Colors.grey.shade500,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildStepper({
    required String value,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _buildStepButton(Icons.remove, onDecrement),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                fontFamily: "Lora",
              ),
            ),
          ),
          _buildStepButton(Icons.add, onIncrement),
        ],
      ),
    );
  }

  Widget _buildStepButton(IconData icon, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.black87, size: 24),
        ),
      ),
    );
  }

  Widget _buildTypographyStepper({
    required String label,
    required String value,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade500,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildSmallStepButton(Icons.remove, onDecrement),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              _buildSmallStepButton(Icons.add, onIncrement),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmallStepButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(icon, size: 18, color: Colors.black54),
      ),
    );
  }

  Widget _buildAlignButton(
    TextAlign value,
    TextAlign current,
    Function(TextAlign) onChanged,
    IconData icon,
  ) {
    bool isSelected = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.black : Colors.grey.shade400,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildBlockStyleButton(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback? onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 60,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? const Color(0xFFB11226) : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFFB11226).withOpacity(0.1),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive
                    ? const Color(0xFFB11226)
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isActive
                      ? const Color(0xFFB11226)
                      : Colors.grey.shade700,
                ),
              ),
            ],
          ),
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

  final Offset _textPosition = const Offset(0.5, 0.4);

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
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          "Design Cover",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFFB11226),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
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
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
          ),
          const SizedBox(width: 8),
        ],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickCoverImage,
                child: Container(
                  width: size.width * 0.65,
                  height: size.height * 0.45,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        // Cover Image
                        _coverImage != null
                            ? Image.file(
                                _coverImage!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: Colors.grey.shade100,
                                child: Center(
                                  child: Icon(
                                    Icons.image_outlined,
                                    size: 60,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),

                        // Title Overlay
                        Positioned(
                          top: 30,
                          left: 20,
                          right: 20,
                          child: Text(
                            _titleController.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: _fontSize,
                              color: _fontColor,
                              fontFamily: _fontFamily,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  blurRadius: 10,
                                  color: Colors.black.withOpacity(0.5),
                                  offset: const Offset(2, 2),
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

            const SizedBox(height: 48),

            /// CONTROLS
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Book Title",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    onChanged: (v) => setState(() {}),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: "Enter a catchy title...",
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Text(
                        "Text Size",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${_fontSize.toInt()} px",
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB11226),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    min: 16,
                    max: 60,
                    value: _fontSize,
                    activeColor: const Color(0xFFB11226),
                    inactiveColor: const Color(0xFFB11226).withOpacity(0.1),
                    onChanged: (v) => setState(() => _fontSize = v),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Font Style",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _fontFamilies.length,
                      itemBuilder: (context, index) {
                        final font = _fontFamilies[index];
                        final isSelected = _fontFamily == font;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ChoiceChip(
                            label: Text(
                              font,
                              style: TextStyle(
                                fontFamily: font,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFFB11226),
                            backgroundColor: Colors.grey.shade100,
                            onSelected: (v) =>
                                setState(() => _fontFamily = font),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Text Color",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: _colors.map((color) {
                      final isSelected = _fontColor == color;
                      return GestureDetector(
                        onTap: () => setState(() => _fontColor = color),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFB11226)
                                  : Colors.grey.shade300,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
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

  @override
  void initState() {
    super.initState();
    print("Draft ID in PostPage: ${widget.draftId}");
  }

  List<String> extractHashtags(String input) {
    final regex = RegExp(r'#[\p{L}\p{M}0-9_]+', unicode: true);
    return regex
        .allMatches(input)
        .map((m) => m.group(0)!.toLowerCase())
        .toSet()
        .toList();
  }

  Future<void> _submitPost() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");

    final uri = Uri.parse("https://bigiluu.com/api/posts/createPost");

    var request = http.MultipartRequest("POST", uri);

    request.headers["Accept"] = "application/json";
    //request.headers["Content-Type"] = "multipart/form-data";

    request.fields["user_id"] = userId ?? "";
    String? coverImageName;

    if (widget.coverImage != null) {
      File? finalCover = widget.coverImage;

      if (finalCover != null) {
        request.files.add(
          await http.MultipartFile.fromPath("cover_images", finalCover.path),
        );

        coverImageName = finalCover.path.split('/').last;
      }
    }
    request.fields["caption"] = _captionController.text;
    String tagText = _hashtagController.text.trim();

    // If user typed hashtags manually
    if (tagText.isNotEmpty) {
      List<String> tags = extractHashtags(tagText);

      // normalize hashtags
      tagText = tags.join(" ");
    }

    // If user didn't type hashtag → auto generate
    if (tagText.isEmpty) {
      List<String> words = [];

      for (var page in widget.pages) {
        for (var block in page.blocks) {
          if (block.type == "text" && block.text != null) {
            words.addAll(
              block.text!
                  .toLowerCase()
                  .replaceAll(
                    RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true),
                    '',
                  )
                  .split(" "),
            );
          }
        }
      }

      words = words.where((w) => w.length > 4).toSet().take(5).toList();

      tagText = words.map((w) => "#$w").join(" ");
    }

    request.fields["hastag"] = tagText;

    // If user typed without #
    /*if (tagText.isNotEmpty && !tagText.startsWith("#")) {
      tagText = "#$tagText";
    }

    request.fields["hastag"] = tagText;*/

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
          "isHeadline": block.isHeadline,
          "fontColor": block.fontColor,
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
    const brandColor = Color(0xFFB11226);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          "Review & Publish",
          style: TextStyle(
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
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Final Preview",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Swipe to review your story pages before publishing.",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),

            // Carousel-like preview
            SizedBox(
              height: size.height * 0.45,
              child: PageView.builder(
                itemCount: widget.pages.length + 1,
                controller: PageController(viewportFraction: 0.8),
                itemBuilder: (context, index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: index == 0
                          ? Colors.white
                          : const Color(0xFFFCF5E5),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        children: [
                          if (index > 0)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 15,
                              child: Container(
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
                            ),
                          index == 0
                              ? _buildCoverPreview()
                              : _buildPagePreview(index - 1),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 40),
            _buildPostInputSection(),
            const SizedBox(height: 48),

            // Publish Button
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setState(() => isLoading = true);
                      await _submitPost();
                      setState(() => isLoading = false);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor,
                minimumSize: const Size(double.infinity, 64),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 10,
                shadowColor: brandColor.withOpacity(0.4),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.rocket_launch_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Publish Story",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  bool isLoading = false;

  Widget _buildCoverPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.coverImage != null)
          Image.file(widget.coverImage!, fit: BoxFit.cover)
        else
          Container(
            color: Colors.grey.shade100,
            child: const Center(
              child: Icon(Icons.book_outlined, size: 48, color: Colors.grey),
            ),
          ),

        // Glossy Shine Overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.2),
                Colors.white.withOpacity(0.05),
                Colors.transparent,
              ],
              stops: const [0, 0.2, 0.5],
            ),
          ),
        ),

        if (widget.title != null)
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Text(
              widget.title ?? "",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (widget.titleFontSize ?? 28) * 0.7,
                color: widget.titleColor ?? Colors.white,
                fontFamily: widget.titleFontFamily ?? "Roboto",
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 12,
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPagePreview(int pageIdx) {
    final page = widget.pages[pageIdx];
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 30, 20, 30),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: page.blocks.map<Widget>((block) {
            if (block.type == "text") {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  block.isHeadline
                      ? (block.text ?? "").toUpperCase()
                      : (block.text ?? ""),
                  style: TextStyle(
                    fontSize: block.isHeadline
                        ? (page.fontSize * 0.8)
                        : (page.fontSize * 0.6),
                    fontWeight: block.isHeadline
                        ? FontWeight.w900
                        : FontWeight.normal,
                    fontFamily: page.fontFamily,
                    color: Color(block.fontColor ?? page.fontColor),
                    height: 1.4,
                  ),
                ),
              );
            }
            if (block.type == "image") {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: block.image != null
                      ? Image.file(block.image!, fit: BoxFit.cover)
                      : (block.imageUrl != null
                            ? Image.network(block.imageUrl!, fit: BoxFit.cover)
                            : const SizedBox()),
                ),
              );
            }
            return const SizedBox();
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPostInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Story Caption",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _captionController,
          maxLines: 3,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
          decoration: InputDecoration(
            hintText: "Give your readers an interesting introduction...",
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Color(0xFFB11226),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          "Relevant Hashtags",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hashtagController,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Color(0xFFB11226),
          ),
          decoration: InputDecoration(
            hintText: "#fantasy #romance #adventure",
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(
              Icons.tag_rounded,
              color: Color(0xFFB11226),
              size: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Color(0xFFB11226),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
          ),
        ),
      ],
    );
  }
}
