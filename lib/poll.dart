import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:bigilu/home.dart';

class PollOption {
  final String id;
  final String text;
  int voteCount;

  PollOption({required this.id, required this.text, required this.voteCount});

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: json['option_id'] ?? '',
      text: json['option_text'] ?? '',
      voteCount: json['vote_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'option_id': id,
    'option_text': text,
    'vote_count': voteCount,
  };
}

class PollPost {
  final String pollId;
  final String title;
  final List<PollOption> options;
  bool hasVoted;
  String? selectedOptionId;
  final String? username;
  final String? profileImage;
  final String? constituency;

  PollPost({
    required this.pollId,
    required this.title,
    required this.options,
    this.hasVoted = false,
    this.selectedOptionId,
    this.username,
    this.profileImage,
    this.constituency,
  });

  factory PollPost.fromJson(Map<String, dynamic> json) {
    var optionsList = json['options'] as List? ?? [];

    return PollPost(
      pollId: json['poll_id']?.toString() ?? json['post_id']?.toString() ?? '',
      title: json['question'] ?? json['title'] ?? '',
      options: optionsList.map((i) => PollOption.fromJson(i)).toList(),
      username: json['username']?.toString(),
      profileImage: json['profile_image']?.toString(),
      constituency: json['constituency']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'poll_id': pollId,
    'question': title,
    'options': options.map((o) => o.toJson()).toList(),
  };

  int get totalVotes => options.fold(0, (sum, item) => sum + item.voteCount);
}

class PollFeedPage extends StatefulWidget {
  const PollFeedPage({super.key});

  @override
  State<PollFeedPage> createState() => _PollFeedPageState();
}

class _PollFeedPageState extends State<PollFeedPage> {
  final String baseUrl =
      "https://bigiluu.com/api/polls"; // Update with your IP for physical device
  List<PollPost> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPolls();
  }

  Future<void> _fetchPolls() async {
    try {
      // For demonstration, if server is not running, we use mock data
      final response = await http
          .get(Uri.parse('$baseUrl/feed'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        List jsonResponse = json.decode(response.body);
        setState(() {
          _posts = jsonResponse.map((data) => PollPost.fromJson(data)).toList();
          _isLoading = false;
        });
      } else {
        _loadMockData();
      }
    } catch (e) {
      _loadMockData();
    }
  }

  void _loadMockData() {
    setState(() {
      _posts = [
        PollPost(
          pollId: "POLL001",
          title: "Which UI framework provides the best performance?",
          options: [
            PollOption(
              id: "PO001",
              text: "Flutter (Skia/Impeller)",
              voteCount: 450,
            ),
            PollOption(
              id: "PO002",
              text: "React Native (Bridge/Fabric)",
              voteCount: 210,
            ),
            PollOption(
              id: "PO003",
              text: "Native (Swift/Kotlin)",
              voteCount: 380,
            ),
          ],
        ),
        PollPost(
          pollId: "POLL002",
          title: "Next project backend technology?",
          options: [
            PollOption(id: "PO004", text: "Node.js (Express)", voteCount: 180),
            PollOption(id: "PO005", text: "Go (Fiber)", voteCount: 120),
            PollOption(id: "PO006", text: "Python (FastAPI)", voteCount: 150),
          ],
        ),
      ];
      _isLoading = false;
    });
  }

  Future<void> _handleVote(PollPost post, PollOption option) async {
    if (post.hasVoted) return;

    // UI Update (Optimistic)
    setState(() {
      option.voteCount++;
      post.hasVoted = true;
      post.selectedOptionId = option.id;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      String userId = prefs.getString("user_id") ?? "";

      await http.post(
        Uri.parse('$baseUrl/vote'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "poll_id": post.pollId,
          "option_id": option.id,
          "user_id": userId,
        }),
      );
    } catch (e) {
      print("Vote error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          "Community Polls",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _fetchPolls,
            icon: const Icon(Icons.refresh, color: Colors.black87),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFB11226)),
            )
          : RefreshIndicator(
              onRefresh: _fetchPolls,
              color: const Color(0xFFB11226),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  return _buildPollCard(_posts[index]);
                },
              ),
            ),
    );
  }

  Widget _buildPollCard(PollPost post) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB11226).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "Trending",
                        style: TextStyle(
                          color: Color(0xFFB11226),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.more_horiz, color: Colors.black26),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  post.title,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: post.options
                  .map((option) => _buildOption(post, option))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Row(
              children: [
                Text(
                  "${post.totalVotes} responses",
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (post.hasVoted)
                  const Text(
                    "Vote recorded",
                    style: TextStyle(
                      color: Color(0xFFB11226),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(PollPost post, PollOption option) {
    final double percentage = post.totalVotes == 0
        ? 0
        : (option.voteCount / post.totalVotes);
    final bool isSelected = post.selectedOptionId == option.id;

    return GestureDetector(
      onTap: () => _handleVote(post, option),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 60,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          border: Border.all(
            color: isSelected
                ? const Color(0xFFB11226)
                : Colors.black.withOpacity(0.08),
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            // Progress Fill
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutQuart,
              widthFactor: post.hasVoted ? percentage : 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      isSelected
                          ? const Color(0xFFB11226).withOpacity(0.15)
                          : Colors.black.withOpacity(0.03),
                      isSelected
                          ? const Color(0xFF8A0C20).withOpacity(0.15)
                          : Colors.black.withOpacity(0.03),
                    ],
                  ),
                ),
              ),
            ),
            // Text Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      option.text,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFFB11226)
                            : Colors.black87,
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (post.hasVoted)
                    Text(
                      "${(percentage * 100).toStringAsFixed(1)}%",
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFFB11226)
                            : Colors.black54,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
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

class CreatePollPage extends StatefulWidget {
  const CreatePollPage({super.key});

  @override
  State<CreatePollPage> createState() => _CreatePollPageState();
}

class _CreatePollPageState extends State<CreatePollPage> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  void _addOption() {
    if (_optionControllers.length < 5) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }

  void _submitPoll() async {
    final prefs = await SharedPreferences.getInstance();

    String userId = prefs.getString("user_id") ?? "";

    final question = _questionController.text.trim();

    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final response = await http.post(
      Uri.parse("https://bigiluu.com/api/polls/create"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "user_id": userId,
        "question": question,
        "options": options,
      }),
    );

    print(response.statusCode);
    print(response.body);

    Map<String, dynamic> data = {};
    try {
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body);
      }
    } catch (e) {
      data = {"error": "Server error: ${response.statusCode}"};
    }

    if (response.statusCode == 200) {
      // Clear cache so feed will fetch new poll
      await prefs.remove('cache_polls');
      await prefs.remove('cache_polls_ts');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(data["message"] ?? "Poll created")));

      final route = Platform.isIOS
          ? CupertinoPageRoute(builder: (_) => const MainShell())
          : MaterialPageRoute(builder: (_) => const MainShell());
      Navigator.pushAndRemoveUntil(context, route, (route) => false);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(data["error"])));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Create Poll",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Question",
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _questionController,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Ask something...",
                hintStyle: TextStyle(color: Colors.black.withOpacity(0.4)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFB11226)),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            const Text(
              "Options",
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(_optionControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[index],
                        style: const TextStyle(color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: "Option ${index + 1}",
                          hintStyle: TextStyle(
                            color: Colors.black.withOpacity(0.4),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.black.withOpacity(0.08),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.black.withOpacity(0.08),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFB11226),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Color(0xFFB11226),
                        ),
                        onPressed: () => _removeOption(index),
                      ),
                  ],
                ),
              );
            }),
            if (_optionControllers.length < 5)
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add, color: Color(0xFFB11226)),
                label: const Text(
                  "Add Option",
                  style: TextStyle(
                    color: Color(0xFFB11226),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 48),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB11226).withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _submitPoll,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFB11226), Color(0xFF8A0C20)],
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        "Create Poll",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
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
