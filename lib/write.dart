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

  PageBlock.text(this.text)
    : type = "text",
      image = null,
      imageUrl = null,
      imageWidth = null;

  PageBlock.image(this.image)
    : type = "image",
      text = null,
      imageUrl = null,
      imageWidth = 200,
      imagePosition = const Offset(0, 0);

  PageBlock.networkImage(this.imageUrl)
    : type = "image",
      text = null,
      image = null,
      imageWidth = 200,
      imagePosition = const Offset(0, 0);
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

  final Map<String, TextEditingController> _controllers = {};

int _getWordLimit(PageData page) {
  bool hasImage =
      page.blocks.any((block) => block.type == "image");

  return hasImage ? 120 : 250;
}

int _countWords(String text) {
  if (text.trim().isEmpty) return 0;
  return text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
}

  @override
  void initState() {
    super.initState();

    if (widget.draftContent != null) {
      _loadDraftContent(widget.draftContent!);
    }

    // ✅ INSERT COVER AS FIRST BLOCK
    if (widget.draftCover != null && widget.draftCover!.isNotEmpty) {
      _pages[0].blocks.insert(0, PageBlock.networkImage(widget.draftCover!));
    }
  }

  void _handleTextChange(
    String value, int pageIndex, int blockIndex) {

  final page = _pages[pageIndex];
  final block = page.blocks[blockIndex];

  int wordLimit = _getWordLimit(page);
  List<String> words =
      value.trim().split(RegExp(r'\s+'));

  // ✅ If limit not reached → just update normally
  if (words.length <= wordLimit) {
    setState(() {
      block.text = value;
    });
    return;
  }

  // ✅ ONLY split when limit exceeded
  List<String> currentWords =
      words.take(wordLimit).toList();

  List<String> remainingWords =
      words.skip(wordLimit).toList();

  setState(() {
    block.text = currentWords.join(" ");

    // Update controller text properly
    String key = "$pageIndex-$blockIndex";
    _controllers[key]?.text = block.text!;
    _controllers[key]?.selection = TextSelection.fromPosition(
      TextPosition(offset: _controllers[key]!.text.length),
    );

    // Create new page ONLY if remaining exists
    if (remainingWords.isNotEmpty) {
      PageData newPage = PageData(
        fontSize: page.fontSize,
        fontFamily: page.fontFamily,
        fontColor: page.fontColor,
      );

      newPage.blocks[0].text =
          remainingWords.join(" ");

      _pages.insert(pageIndex + 1, newPage);
    }
  });

  Future.delayed(const Duration(milliseconds: 100), () {
    _pageController.jumpToPage(pageIndex + 1);
  });
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
      String url = "http://192.168.29.182:3000/api/posts/createPost";

      Map<String, dynamic> body = {
        "user_id": currentUserId,
        "content": contentJson,
        "caption": "",
      };

      // If draft exists → delete first
      if (widget.draftId != null) {
        await http.delete(
          Uri.parse(
            "http://192.168.29.182:3000/api/draft/deleteDraft/${widget.draftId}",
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
          fontSize: (page['fontSize'] ?? 18).toDouble(),
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
                  "http://192.168.29.182:3000/Uploads/draft_covers/$imageName";

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
    PageData(fontSize: 18, fontFamily: "Roboto", fontColor: Colors.black.value),
  ];

  Future<void> saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");

    final uri = Uri.parse("http://192.168.29.182:3000/api/draft/saveDraft");

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

    var response = await request.send();

    if (response.statusCode == 200) {
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
        _pages[index].blocks.add(PageBlock.image(File(image.path)));

        // Add new text block after image
        _pages[index].blocks.add(PageBlock.text(""));
      });
    }
  }

  void _removeImageBlock(int pageIndex, int blockIndex) {
    setState(() {
      _pages[pageIndex].blocks.removeAt(blockIndex);

      // Optional: remove empty text block above/below if needed
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
    });
  }

  double _fontSize = 18;
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
          fontSize: 18,
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
        await saveDraft(); // 🔥 Auto save when back pressed
        return true; // allow page to close
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
      onPressed: () {
        saveDraft();
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
                          child: ListView.builder(
                            itemCount: _pages[index].blocks.length,
                            itemBuilder: (context, blockIndex) {
                              final block = _pages[index].blocks[blockIndex];
                              if (block.type == "text") {

  String key = "$index-$blockIndex";

  if (!_controllers.containsKey(key)) {
    _controllers[key] =
        TextEditingController(text: block.text ?? "");
  }

  return TextField(
    controller: _controllers[key],
    onChanged: (value) {
      _handleTextChange(value, index, blockIndex);
    },
    maxLines: null,
    style: TextStyle(
      fontSize: _pages[index].fontSize,
      fontFamily: _pages[index].fontFamily,
      color: Color(_pages[index].fontColor),
    ),
    decoration: const InputDecoration(
      hintText: "Write your heart...",
      border: InputBorder.none,
    ),
  );
}

if (block.type == "image") {

  // ===============================
  // LOCAL IMAGE
  // ===============================
  if (block.image != null) {
    return Column(
      children: [
        SizedBox(
  height: 350,
  child: LayoutBuilder(
    builder: (context, constraints) {
      return Stack(
        children: [
          Positioned(
            left: (block.imagePosition?.dx ?? 0.5) *
                constraints.maxWidth,
            top: (block.imagePosition?.dy ?? 0.0) *
                constraints.maxHeight,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  double newX =
                      (block.imagePosition?.dx ?? 0.5) +
                      (details.delta.dx /
                          constraints.maxWidth);

                  double newY =
                      (block.imagePosition?.dy ?? 0.0) +
                      (details.delta.dy /
                          constraints.maxHeight);

                  block.imagePosition = Offset(
                    newX.clamp(0.0, 1.0),
                    newY.clamp(0.0, 1.0),
                  );
                });
              },
              child: Image.file(
                block.image!,
                width: block.imageWidth ?? 200,
              ),
            ),
          ),

          // Delete Button
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () =>
                  _removeImageBlock(index, blockIndex),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      );
    },
  ),
),

        // Width Slider
        Slider(
          min: 100,
          max: 300,
          value: block.imageWidth ?? 200,
          onChanged: (value) {
            setState(() {
              block.imageWidth = value;
            });
          },
        ),
      ],
    );
  }

  // ===============================
  // NETWORK IMAGE
  // ===============================
  if (block.imageUrl != null &&
      block.imageUrl!.isNotEmpty) {

    return Column(
      children: [
        SizedBox(
  height: 350,
  child: LayoutBuilder(
    builder: (context, constraints) {
      return Stack(
        children: [
          Positioned(
            left: (block.imagePosition?.dx ?? 0.5) *
                constraints.maxWidth,
            top: (block.imagePosition?.dy ?? 0.0) *
                constraints.maxHeight,
            child: Image.network(
              block.imageUrl!,
              width: block.imageWidth ?? 200,
            ),
          ),
        ],
      );
    },
  ),
),

        // Width Slider
        Slider(
          min: 100,
          max: 300,
          value: block.imageWidth ?? 200,
          onChanged: (value) {
            setState(() {
              block.imageWidth = value;
            });
          },
        ),
      ],
    );
  }
}
                              return const SizedBox();
                            },
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
                  PopupMenuButton<double>(
                    icon: const Icon(Icons.text_fields),
                    onSelected: (value) {
                      setState(() {
                        _fontSize = value;
                        _pages[_currentPage].fontSize =
                            value; // Update current page
                      });
                    },
                    itemBuilder: (context) => [16, 18, 20, 22, 24, 28]
                        .map(
                          (s) => PopupMenuItem(
                            value: s.toDouble(),
                            child: Text("Size: $s"),
                          ),
                        )
                        .toList(),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.font_download),
                    onSelected: (value) {
                      setState(() {
                        _fontFamily = value;
                        _pages[_currentPage].fontFamily =
                            value; // Update current page
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
                        _pages[_currentPage].fontColor =
                            value.value; // Update current page
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
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: () => _pickImageForPage(_currentPage),
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
        style: TextStyle(
          fontSize: 16,
          color: Color(0xFF800000),
        ),
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
    final maxWidth = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;

    return Positioned(
      left: _textPosition.dx * maxWidth,
      top: _textPosition.dy * maxHeight,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            double newX =
                _textPosition.dx +
                (details.delta.dx / maxWidth);

            double newY =
                _textPosition.dy +
                (details.delta.dy / maxHeight);

            // Clamp safely between 0 and 1
            newX = newX.clamp(0.0, 1.0);
            newY = newY.clamp(0.0, 1.0);

            _textPosition = Offset(newX, newY);
          });
        },
        child: Text(
          _titleController.text,
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

    final uri = Uri.parse("http://192.168.29.182:3000/api/posts/createPost");

    var request = http.MultipartRequest("POST", uri);

    request.fields["user_id"] = userId ?? "";
    String? coverImageName;

    if (widget.coverImage != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          "cover_images",
          widget.coverImage!.path,
        ),
      );

      coverImageName = widget.coverImage!.path.split('/').last;
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

    if (_pickedImage != null) {
      request.files.add(
        await http.MultipartFile.fromPath("cover_images", _pickedImage!.path),
      );
    }

    request.fields["titleFontSize"] =
    widget.titleFontSize?.toString() ?? "28";

request.fields["titleColor"] =
    widget.titleColor?.value.toString() ?? Colors.white.value.toString();

request.fields["titleFontFamily"] =
    widget.titleFontFamily ?? "Roboto";

request.fields["titlePositionX"] =
    widget.titlePosition?.dx.toString() ?? "0.5";

request.fields["titlePositionY"] =
    widget.titlePosition?.dy.toString() ?? "0.4";


    var response = await request.send();

    if (response.statusCode == 200) {
      if (widget.draftId != null) {
        await http.delete(
          Uri.parse(
            "http://192.168.29.182:3000/api/draft/deleteDraft/${widget.draftId}",
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
    final posX =
        (widget.titlePosition?.dx ?? 0.5) * constraints.maxWidth;

    final posY =
        (widget.titlePosition?.dy ?? 0.4) * constraints.maxHeight;

    return Positioned(
      left: posX,
      top: posY,
      child: Text(
        widget.title ?? "",
        style: TextStyle(
          fontSize: widget.titleFontSize ?? 28,
          color: widget.titleColor ?? Colors.white,
          fontFamily: widget.titleFontFamily ?? "Roboto",
          fontWeight: FontWeight.bold,
        ),
      ),
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

                   // LOCAL IMAGE
if (block.type == "image" && block.image != null) {
  return SizedBox(
  height: 350,
  child: LayoutBuilder(
    builder: (context, constraints) {
      return Stack(
        children: [
          Positioned(
            left: (block.imagePosition?.dx ?? 0.5) *
                constraints.maxWidth,
            top: (block.imagePosition?.dy ?? 0.0) *
                constraints.maxHeight,
            child: Image.file(
              block.image!,
              width: block.imageWidth ?? 200,
            ),
          ),
        ],
      );
    },
  ),
);
}

// NETWORK IMAGE (if you support imageUrl)
if (block.type == "image" &&
    block.imageUrl != null &&
    block.imageUrl!.isNotEmpty) {
  return SizedBox(
  height: 350,
  child: LayoutBuilder(
    builder: (context, constraints) {
      return Stack(
        children: [
          Positioned(
            left: (block.imagePosition?.dx ?? 0.5) *
                constraints.maxWidth,
            top: (block.imagePosition?.dy ?? 0.0) *
                constraints.maxHeight,
            child: Image.network(
              block.imageUrl!,
              width: block.imageWidth ?? 200,
            ),
          ),
        ],
      );
    },
  ),
);
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