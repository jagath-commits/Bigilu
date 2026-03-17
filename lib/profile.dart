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

  String? _selectedConstituency;

  final List<String> _constituencies = [
    "Gummidipoondi", "Ponneri", "Tiruttani", "Tiruvallur", "Poonamallee",
    "Avadi", "Maduravoyal", "Ambattur", "Madavaram", "Thiruvottiyur",
    "Dr. Radhakrishnan Nagar", "Perambur", "Kolathur", "Villivakkam", "Thiru-Vi-Ka-Nagar",
    "Egmore", "Royapuram", "Harbour", "Chepauk-Thiruvallikeni", "Thousand Lights",
    "Anna Nagar", "Virugampakkam", "Saidapet", "T. Nagar", "Mylapore",
    "Velachery", "Sholinganallur", "Alandur", "Sriperumbudur", "Pallavaram",
    "Tambaram", "Chengalpattu", "Thiruporur", "Cheyyur", "Madurantakam",
    "Uthiramerur", "Kancheepuram", "Arakkonam", "Sholingur", "Katpadi",
    "Ranipet", "Arcot", "Vellore", "Anaikattu", "K. V. Kuppam",
    "Gudiyattam", "Vaniyambadi", "Ambur", "Jolarpet", "Tirupattur",
    "Uthangarai", "Bargur", "Krishnagiri", "Veppanahalli", "Hosur",
    "Thalli", "Palacode", "Pennagaram", "Dharmapuri", "Pappireddippatti",
    "Harur", "Chengam", "Tiruvannamalai", "Kilpennathur", "Kalasapakkam",
    "Polur", "Arani", "Cheyyar", "Vandavasi", "Gingee", "Mailam",
    "Tindivanam", "Vanur", "Villupuram", "Vikravandi", "Tirukoilur",
    "Ulundurpettai", "Rishivandiyam", "Sankarapuram", "Kallakurichi",
    "Gangavalli", "Attur", "Yercaud", "Omalur", "Mettur", "Edappadi",
    "Sankagiri", "Salem West", "Salem North", "Salem South", "Veerapandi",
    "Rasipuram", "Senthamangalam", "Namakkal", "Paramathi Velur", "Tiruchengode",
    "Kumarapalayam", "Erode East", "Erode West", "Modakurichi", "Perundurai",
    "Bhavani", "Anthiyur", "Gobichettipalayam", "Bhavanisagar", "Dharapuram",
    "Kangeyam", "Avinashi", "Tiruppur North", "Tiruppur South", "Palladam",
    "Udumalpet", "Madathukulam", "Udhagamandalam", "Gudalur", "Coonoor",
    "Mettuppalayam", "Sulur", "Kavundampalayam", "Coimbatore North", "Thondamuthur",
    "Coimbatore South", "Singanallur", "Kinathukadavu", "Pollachi", "Valparai",
    "Palani", "Oddanchatram", "Athoor", "Nilakkottai", "Natham", "Dindigul",
    "Vedasandur", "Aravakurichi", "Karur", "Krishnarayapuram", "Kulithalai",
    "Manapparai", "Srirangam", "Tiruchirappalli West", "Tiruchirappalli East",
    "Thiruverumbur", "Lalgudi", "Mannachanallur", "Musiri", "Thuraiyur",
    "Perambalur", "Kunnam", "Ariyalur", "Jayankondam", "Chidambaram",
    "Kattumannarkoil", "Cuddalore", "Panruti", "Kurinjipadi", "Bhuvanagiri",
    "Neyveli", "Vridhachalam", "Tittakudi", "Sirkazhi", "Mayiladuthurai",
    "Poompuhar", "Nagapattinam", "Kilvelur", "Vedaranyam", "Thiruthuraipoondi",
    "Mannargudi", "Thiruvarur", "Nannilam", "Thiruvidaimarudur",
    "Kumbakonam", "Papanasam", "Thiruvaiyaru", "Thanjavur", "Orathanadu",
    "Pattukkottai", "Peravurani", "Gandharvakottai", "Viralimalai", "Pudukkottai",
    "Thirumayam", "Alangudi", "Aranthangi", "Karaikudi", "Tiruppattur (Sivaganga)",
    "Sivaganga", "Manamadurai", "Melur", "Madurai East", "Madurai North",
    "Madurai Central", "Madurai West", "Madurai South", "Thirupparankundram",
    "Thirumangalam", "Usilampatti", "Andipatti", "Periyakulam", "Bodinayakanur",
    "Cumbum", "Theni", "Rajapalayam", "Srivilliputhur", "Sattur", "Sivakasi",
    "Virudhunagar", "Aruppukkottai", "Tiruchuli", "Paramakudi", "Tiruvadanai",
    "Ramanathapuram", "Mudukulathur", "Vilathikulam", "Thoothukkudi", "Tiruchendur",
    "Srivaikuntam", "Ottapidaram", "Kovilpatti", "Sankarankovil", "Vasudevanallur",
    "Kadayanallur", "Tenkasi", "Alangulam", "Tirunelveli", "Ambasamudram",
    "Palayamkottai", "Nanguneri", "Radhapuram", "Kanniyakumari", "Nagercoil",
    "Colachel", "Padmanabhapuram", "Vilavancode", "Killiyoor"
  ];

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
      path = "uploads/profile_images/$path";
    }

    // ✅ Return complete HTTPS URL
    return "https://bigiluu.com/$path";
  }

  @override
  void initState() {
    super.initState();
    _constituencies.sort(); // 🔥 Ensure alphabetical order
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
          
          // Try both keys for backward compatibility
          String backendConstituency = data['constituency'] ?? data['membership_id'] ?? "";
          if (_constituencies.contains(backendConstituency)) {
            _selectedConstituency = backendConstituency;
          }

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
    // Check mandatory fields
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _selectedConstituency == null ||
        _selectedConstituency!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all mandatory fields (*)"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
      // Send to both keys to ensure backend receives it correctly
      request.fields["constituency"] = _selectedConstituency ?? "";
      request.fields["membership_id"] = _selectedConstituency ?? "";

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

        // 🔥 GO TO HOME PAGE
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
            (route) => false,
          );
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

      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text(
                'Image selected! Click Save to update.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFB11226),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
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
      backgroundColor: const Color(0xFFFAFAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomePage()),
              (route) => false,
            );
          },
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: const Text(
          "Edit Profile",
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Roboto',
            letterSpacing: 0.3,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.06,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      /// Profile Avatar Section
                      Center(child: _buildProfessionalAvatar()),

                      SizedBox(height: screenHeight * 0.04),

                      /// Input Fields Section
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.06),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _buildProfessionalInput(
                              'Full Name *',
                              _nameController,
                            ),
                            const SizedBox(height: 16),
                            _buildProfessionalInput(
                              'Mobile Number *',
                              _mobileController,
                              readOnly: true,
                            ),
                            const SizedBox(height: 16),
                            _buildProfessionalInput(
                              'Email *',
                              _emailController,
                            ),
                            const SizedBox(height: 16),
                            _buildConstituencyDropdown(),
                          ],
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.04),

                      /// Save Button
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFB11226).withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isLoading ? null : saveProfile,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: double.infinity,
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFB11226),
                                    Color(0xFF8A0C20),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: _isLoading
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white.withOpacity(0.9),
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Save Changes',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                              fontFamily: 'Roboto',
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
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
      bottomNavigationBar: _buildProfessionalBottomNav(context),
    );
  }

  /// Professional Avatar with Enhanced Styling
  Widget _buildProfessionalAvatar() {
    ImageProvider provider;

    if (_image != null) {
      provider = FileImage(_image!);
    } else if (_networkImageUrl != null) {
      provider = NetworkImage(_networkImageUrl!);
    } else {
      provider = const NetworkImage('https://i.stack.imgur.com/l60Hf.png');
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onTap: _showImagePickerOptions,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB11226).withOpacity(0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundImage: provider,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showImagePickerOptions,
              borderRadius: BorderRadius.circular(20),
              splashColor: Colors.white.withOpacity(0.4),
              highlightColor: Colors.white.withOpacity(0.2),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFB11226), Color(0xFF8A0C20)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB11226).withOpacity(0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Professional Constituency Dropdown
  Widget _buildConstituencyDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Constituency *',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
            fontFamily: 'Roboto',
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF2196F3).withOpacity(0.3),
              width: 1.3,
            ),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedConstituency,
              hint: Text(
                'Select Constituency',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'Roboto',
                  color: Colors.grey.shade400,
                ),
              ),
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade600),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'Roboto',
                color: Colors.black87,
              ),
              items: _constituencies.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedConstituency = newValue;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Professional Input Field
  Widget _buildProfessionalInput(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
            fontFamily: 'Roboto',
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: readOnly
                  ? Colors.grey.shade300
                  : const Color(0xFF2196F3).withOpacity(0.3),
              width: 1.3,
            ),
            color: readOnly ? Colors.grey.shade100 : Colors.white,
          ),
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'Roboto',
              color: Colors.black87,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Enter $label',
              hintStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                fontFamily: 'Roboto',
                color: Colors.grey.shade400,
              ),
              suffixIcon: readOnly
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        Icons.lock_rounded,
                        color: Colors.grey.shade400,
                        size: 18,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Professional Bottom Navigation - Premium Enhanced
  Widget _buildProfessionalBottomNav(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: const Color(0xFFB11226), width: 2.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPremiumNavItem(
                context,
                Icons.person_rounded,
                'Profile',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfilePage(userId: widget.userId),
                    ),
                  );
                },
                isActive: true,
              ),
              _buildPremiumNavItem(context, Icons.tag_rounded, 'Discover', () {
                final route = Platform.isIOS
                    ? CupertinoPageRoute(builder: (_) => const HashtagPage())
                    : MaterialPageRoute(builder: (_) => const HashtagPage());
                Navigator.push(context, route);
              }),
              _buildPremiumNavItem(context, Icons.home_rounded, 'Home', () {
                final route = Platform.isIOS
                    ? CupertinoPageRoute(builder: (_) => const HomePage())
                    : MaterialPageRoute(builder: (_) => const HomePage());
                Navigator.push(context, route);
              }),
              _buildPremiumNavItem(context, Icons.edit_rounded, 'Write', () {
                final route = Platform.isIOS
                    ? CupertinoPageRoute(builder: (_) => const WritePage())
                    : MaterialPageRoute(builder: (_) => const WritePage());
                Navigator.push(context, route);
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// Premium Navigation Item with Enhanced Styling
  Widget _buildPremiumNavItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool isActive = false,
  }) {
    double screenWidth = MediaQuery.of(context).size.width;
    double iconSize = screenWidth < 360 ? 23 : 28;
    double fontSize = screenWidth < 360 ? 9.5 : 10.5;

    Color activeColor = const Color(0xFFB11226);
    Color inactiveColor = Colors.grey.shade500;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        splashColor: activeColor.withOpacity(0.2),
        highlightColor: activeColor.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: isActive
              ? BoxDecoration(
                  color: activeColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: activeColor.withOpacity(0.4),
                    width: 1.3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                )
              : BoxDecoration(borderRadius: BorderRadius.circular(14)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? activeColor : inactiveColor,
                size: iconSize,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? activeColor : inactiveColor,
                  fontSize: fontSize,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                  fontFamily: 'Roboto',
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show Image Picker Options
  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text(
                'Gallery',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text(
                'Camera',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                ),
              ),
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
}
