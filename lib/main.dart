import 'dart:io' show Platform;
import 'package:bigilu/home.dart';
import 'package:bigilu/otp.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  String? token = prefs.getString("token");

  runApp(MyApp(token: token));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  final String? token;

  const MyApp({super.key, required this.token});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() async {
    _appLinks = AppLinks();

    // App opened from closed state
    final Uri? initialUri = await _appLinks.getInitialLink();

    if (initialUri != null && initialUri.pathSegments.contains('post')) {
      final postId = initialUri.pathSegments.last;

      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => HomePage(deepLinkPostId: postId)),
      );
    }

    // App already running
    _sub = _appLinks.uriLinkStream.listen((Uri uri) {
      if (uri.pathSegments.contains('post')) {
        final postId = uri.pathSegments.last;

        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => HomePage(deepLinkPostId: postId)),
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return CupertinoApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        home: widget.token != null ? const HomePage() : const LoginPage(),
      );
    }

    return MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.0)),
          child: child!,
        );
      },
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: widget.token != null ? const HomePage() : const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  bool isLoading = false;

  Future<void> sendOtpFirebase() async {
    if (!validateInput()) return;

    setState(() => isLoading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      timeout: const Duration(seconds: 30),
      phoneNumber: "+91${phoneController.text.trim()}",
      verificationCompleted: (credential) async {
        // Auto-verification (sometimes happens on Android)
        await FirebaseAuth.instance.signInWithCredential(credential);

        setState(() => isLoading = false);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      },
      verificationFailed: (e) {
        setState(() => isLoading = false);
        showError(e.message ?? "OTP failed");
      },
      codeSent: (verificationId, resendToken) {
        setState(() => isLoading = false);

        Navigator.push(
          context,
          Platform.isIOS
              ? CupertinoPageRoute(
                  builder: (_) => OtpPage(
                    phone: "+91${phoneController.text.trim()}",
                    verificationId: verificationId, // ✅ pass this
                  ),
                )
              : MaterialPageRoute(
                  builder: (_) => OtpPage(
                    phone: "+91${phoneController.text.trim()}",
                    verificationId: verificationId, // ✅ pass this
                  ),
                ),
        );
      },

      codeAutoRetrievalTimeout: (verificationId) {},
    );
  }

  void showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool validateInput() {
    if (phoneController.text.length != 10) {
      showError("Enter valid 10 digit number");
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Light theme background
          Container(color: const Color(0xFFF8F9FA)),



          // Top Center Logo - Bigger and Lower
          Positioned(
            top: MediaQuery.of(context).padding.top + 30, // Moved lower
            left: 0,
            right: 0,
            child: Center(
              child: Image.asset(
                "assets/images/bigilu_logo21.png",
                height: 90, // Increased size
                width: 240, // Increased size
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),

          // SafeArea starts here
          SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(), // Remove bounce animation
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 24 : 48,
                vertical: 20,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom -
                      40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        // Premium header with logo
                        const SizedBox(height: 20),

                        // Vertical Space to maintain phone field position
                        SizedBox(
                          height: screenHeight * 0.18,
                        ), // Increased from 0.15 to move field lower

                        SizedBox(
                          height: screenHeight * 0.05,
                        ), // Increased from 0.04 for more shift
                        // Features cards (optional)
                        SizedBox(height: screenHeight * 0.04),

                        // Phone Input Field - Reduced Size
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.black.withOpacity(0.08),
                              width: 1.5,
                            ),
                            color: Colors.white,
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
                              Text(
                                "Mobile Number",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black.withOpacity(0.7),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                  letterSpacing: 1.0,
                                ),
                                decoration: InputDecoration(
                                  hintText: "9876543210",
                                  hintStyle: TextStyle(
                                    color: Colors.black.withOpacity(0.2),
                                    fontSize: 16,
                                  ),
                                  filled: false,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  prefixText: "+91  ",
                                  prefixStyle: const TextStyle(
                                    color: Color(0xFFB11226),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.04),

                        // Send OTP Button - Hero Button
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
                              onTap: isLoading
                                  ? null
                                  : () {
                                      if (validateInput()) {
                                        sendOtpFirebase();
                                      }
                                    },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
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
                                  child: isLoading
                                      ? SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white.withOpacity(0.9),
                                                ),
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Text(
                                              "Send OTP",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.arrow_forward,
                                              color: Colors.white.withOpacity(
                                                0.9,
                                              ),
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.03),

                        // Privacy notice
                        Text(
                          "We'll send you a one-time code",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black.withOpacity(0.5),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),

                    // Footer
                    Column(
                      children: [
                        Container(
                          height: 1,
                          color: Colors.black.withOpacity(0.05),
                          margin: EdgeInsets.symmetric(
                            vertical: screenHeight * 0.03,
                          ),
                        ),
                        Column(
                          children: [
                            Text(
                              "Powered by",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withOpacity(0.4),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 20,
                              ),
                              margin: const EdgeInsets.only(
                                bottom: 30,
                              ), // Move slightly upper
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.black.withOpacity(0.05),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                "assets/images/codereadlogo.png",
                                height: 110, // Even bigger watermark size
                                width:
                                    screenWidth * 0.85, // Occupies more width
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ],
                        ),
                      ],
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
