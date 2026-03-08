import 'dart:convert';
import 'dart:io' show Platform, File;
import 'package:bigilu/hashtag.dart';
import 'package:bigilu/home.dart';
import 'package:bigilu/profile1.dart';
import 'package:bigilu/write.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';

class EditProfilePage extends StatefulWidget {
  final String userId;
  const EditProfilePage({super.key, required this.userId});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  Future<String?> getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _idController = TextEditingController();

  File? _image;
  String? _networkImageUrl;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  final String baseUrl = "https://bigiluu.com/api";

  // ✅ Helper function to normalize image URLs
  // ✅ Helper function to normalize image URLs
  String fullUrl(String? path) {
    if (path == null || path.isEmpty) {
      return "";
    }

    // ✅ If already a complete URL, ensure HTTPS and normalize path
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
        return domain + "/" + pathPart;
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
      path = "uploads/profile_images/$path";
    }

    // ✅ Return complete HTTPS URL
    return "https://bigiluu.com/$path";
  }

  @override
  void initState() {
    super.initState();
    print("🔍 DEBUG: EditProfilePage init with userId: ${widget.userId}");
    _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    await _loadProfileFromBackend();
  }

  Future<void> _loadProfileFromBackend() async {
    try {
      final url = "$baseUrl/profile/profile/${widget.userId}";
      print("🔍 DEBUG: Calling API: $url");

      final response = await http.get(Uri.parse(url));

      print("🔍 DEBUG: Response status: ${response.statusCode}");
      print("🔍 DEBUG: Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("🔍 DEBUG: Parsed data: $data");

        setState(() {
          _nameController.text = data['username'] ?? "";
          _mobileController.text = data['phoneno']?.toString() ?? "";
          _emailController.text = data['mail_id'] ?? "";
          _idController.text = data['membership_id'] ?? "";

          // ✅ Use fullUrl() to normalize image paths
          if (data['profile_image'] != null &&
              data['profile_image'].toString().isNotEmpty) {
            _networkImageUrl = fullUrl(data['profile_image']);
            print("🔍 DEBUG: Final image URL: $_networkImageUrl");
          } else {
            _networkImageUrl = null;
            print("🔍 DEBUG: No profile image");
          }
        });
      } else {
        print(
          "❌ Profile load failed: ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      print("❌ ERROR fetching profile: $e");
    }
  }

  // ===============================
  // SAVE PROFILE & RETURN DATA
  // ===============================
  Future<void> saveProfile() async {
    setState(() => _isLoading = true);

    try {
      var request = http.MultipartRequest(
        "PUT",
        Uri.parse("$baseUrl/profile/saveProfile"),
      );

      request.fields["user_id"] = widget.userId;
      request.fields["phoneno"] = _mobileController.text;
      request.fields["username"] = _nameController.text;
      request.fields["mail_id"] = _emailController.text;
      request.fields["membership_id"] = _idController.text;

      if (_image != null) {
        final mimeType = lookupMimeType(_image!.path);
        if (mimeType != null) {
          final mimeSplit = mimeType.split('/');
          request.files.add(
            await http.MultipartFile.fromPath(
              "profile_images",
              _image!.path,
              contentType: MediaType(mimeSplit[0], mimeSplit[1]),
            ),
          );

          print("✅ DEBUG: Image file added to request");
        }
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      print("🔍 DEBUG: Save response status: ${response.statusCode}");
      print("🔍 DEBUG: Save response body: $responseData");

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(responseData);

        // ✅ Use fullUrl() to normalize image paths
        String? imageUrl;
        if (data['profile_image'] != null) {
          imageUrl = fullUrl(data['profile_image']);
          print("✅ DEBUG: Updated profile image URL: $imageUrl");
        }

        final updatedName = data['username'] ?? _nameController.text;

        await _saveLocally(updatedName, _image, imageUrl);

        // 🔥 POP AND RETURN UPDATED USERNAME
        if (mounted) {
          Navigator.pop(context, {
            "username": updatedName,
            "profile_image": imageUrl,
          });
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $responseData")));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print("❌ SAVE ERROR: $e");
    }
  }

  Future<void> _saveLocally(
    String username,
    File? imageFile,
    String? imageUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Save username
    prefs.setString("username", username);

    // Save local image path if user picked new image
    if (imageFile != null) {
      prefs.setString("profile_image_path", imageFile.path);
      prefs.remove("profile_image_url"); // remove old URL
    } else if (imageUrl != null) {
      prefs.setString("profile_image_url", imageUrl);
      prefs.remove("profile_image_path"); // remove old local path
    }
  }

  // ===============================
  // IMAGE PICKER
  // ===============================
  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  // ===============================
  // UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Edit Profile"),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.05,
                vertical: 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),

                      _buildAvatar(),

                      SizedBox(height: screenHeight * 0.03),

                      _buildInput('Name', _nameController),

                      _buildInput(
                        'Mobile Number',
                        _mobileController,
                        readOnly: true,
                      ),

                      _buildInput('Email', _emailController),

                      _buildInput('Membership ID', _idController),

                      SizedBox(height: screenHeight * 0.03),

                      SizedBox(
                        width: double.infinity,
                        height: screenHeight * 0.06,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF800000),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isLoading ? null : saveProfile,
                          icon: const Icon(Icons.save),
                          label: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ),

                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  // ===============================
  // AVATAR
  // ===============================
  Widget _buildAvatar() {
    ImageProvider provider;

    if (_image != null) {
      provider = FileImage(_image!);
    } else if (_networkImageUrl != null) {
      provider = NetworkImage(_networkImageUrl!);
    } else {
      provider = const NetworkImage('https://i.stack.imgur.com/l60Hf.png');
    }

    return GestureDetector(
      onTap: _showImagePickerOptions,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(radius: 50, backgroundImage: provider),
          Positioned(
            bottom: 0,
            right: 0,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.amber,
              child: const Icon(Icons.edit, size: 16, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: readOnly ? Colors.grey.shade200 : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: BottomAppBar(
        height: 60,
        color: const Color(0xFF800000),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(Icons.person, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(userId: widget.userId),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.tag, color: Colors.white),
              onPressed: () {
                final route = Platform.isIOS
                    ? CupertinoPageRoute(builder: (_) => const HashtagPage())
                    : MaterialPageRoute(builder: (_) => const HashtagPage());
                Navigator.push(context, route);
              },
            ),
            IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              onPressed: () {
                final route = Platform.isIOS
                    ? CupertinoPageRoute(builder: (_) => const HomePage())
                    : MaterialPageRoute(builder: (_) => const HomePage());
                Navigator.push(context, route);
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: () {
                final route = Platform.isIOS
                    ? CupertinoPageRoute(builder: (_) => const WritePage())
                    : MaterialPageRoute(builder: (_) => const WritePage());
                Navigator.push(context, route);
              },
            ),
          ],
        ),
      ),
    );
  }
}
