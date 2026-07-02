import 'dart:io' show Platform;
import 'package:bigilu/home.dart'; // MainShell + HomePage
import 'package:bigilu/otp.dart';
import 'package:bigilu/password_login.dart';
import 'package:bigilu/profile1.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@drawable/ic_notification');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'channel_id',
          'channel_name',
          description: 'This is important channel',
          importance: Importance.max,
        ),
      );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _initializeNotifications();

  final title =
      message.notification?.title ??
      message.data['title'] ??
      'New Notification';
  final body =
      message.notification?.body ??
      message.data['body'] ??
      'You have a new update';

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'channel_id',
        'channel_name',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  await _initializeNotifications();

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

Future<void> sendTokenToServer(String token) async {
  final prefs = await SharedPreferences.getInstance();
  String? userId = prefs.getString("user_id");

  if (userId == null) {
    print("⚠️ Sending token without user_id");
  }

  var response = await http.post(
    Uri.parse("https://bigiluu.com/api/posts/save-token"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({"user_id": userId, "fcm_token": token}),
  );

  print("API STATUS: ${response.statusCode}");
  print("API RESPONSE: ${response.body}");
}

class MyApp extends StatefulWidget {
  final String? token;

  const MyApp({super.key, required this.token});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  // ONLY CHANGED PARTS ARE MARKED ✅

  @override
  void initState() {
    super.initState();

    _initDeepLinks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFirebase();

      checkForceUpdate();
    });
  }

  Future<void> checkForceUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse("https://bigiluu.com/api/app-version"),
      );

      final data = jsonDecode(response.body);

      final latestVersion = data["latest_version"];

      final forceUpdate = data["force_update"];

      if (currentVersion != latestVersion && forceUpdate == true) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) {
            return AlertDialog(
              title: const Text("Update Required"),
              content: const Text("Please update Bigilu to continue."),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    await launchUrl(
                      Uri.parse(data["playstore_url"]),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: const Text("Update Now"),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      print("VERSION ERROR: $e");
    }
  }

  Future<void> _initFirebase() async {
    NotificationSettings settings = await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    print("Permission: ${settings.authorizationStatus}");

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print("🔥 FULL MESSAGE: ${message.data}");
      await _showNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("🔥 BACKGROUND CLICK");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTap(message);
      });
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        print("🔥 APP OPENED FROM TERMINATED");
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationTap(message);
        });
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      print("NEW FCM TOKEN: $newToken");
      await sendTokenToServer(newToken);
    });

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await sendTokenToServer(token);
      }
    } catch (e) {
      print("🔥 FCM Token Error: $e");
    }
    print("🔥 FINAL TOKEN: $token");
  }

  Future<void> _showNotification(RemoteMessage message) async {
    final title =
        message.notification?.title ??
        message.data['title'] ??
        'New Notification';
    final body =
        message.notification?.body ??
        message.data['body'] ??
        'You have a new update';

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'channel_id',
          'channel_name',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final postId = message.data['post_id']?.toString();
    final userId = message.data['user_id']?.toString();

    if (postId != null && userId != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ProfilePage(
            userId: userId,
            isPublicView: true,
            initialPostId: postId,
          ),
        ),
      );
    }
  }

  void _initDeepLinks() async {
    _appLinks = AppLinks();

    // App opened from closed state
    final Uri? initialUri = await _appLinks.getInitialLink();

    if (initialUri != null && initialUri.pathSegments.contains('post')) {
      final postId = initialUri.pathSegments.last;
      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString("user_id");

      if (userId == null) return;

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ProfilePage(
            userId: userId,
            isPublicView: true,
            initialPostId: postId,
          ),
        ),
      );
    }

    // App already running
    _sub = _appLinks.uriLinkStream.listen((Uri uri) async {
      if (uri.pathSegments.contains('post')) {
        final postId = uri.pathSegments.last;

        final prefs = await SharedPreferences.getInstance();
        String? userId = prefs.getString("user_id");

        if (userId == null) return;

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ProfilePage(
              userId: userId,
              isPublicView: true,
              initialPostId: postId,
            ),
          ),
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
        home: widget.token != null
            ? const MainShell()
            : const PasswordLoginPage(),
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
      home: widget.token != null
          ? const MainShell()
          : const PasswordLoginPage(),
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

  /* Future<void> sendOtpFirebase() async {
    if (!validateInput()) return;

    setState(() => isLoading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      timeout: const Duration(seconds: 30),
      phoneNumber: "+91${phoneController.text.trim()}",
      verificationCompleted: (credential) async {
  await FirebaseAuth.instance.signInWithCredential(credential);

  // 🔥 CALL BACKEND TO GET USER_ID
  var response = await http.post(
    Uri.parse("https://bigiluu.com/api/login"), // ⚠️ create this API
    body: {
      "phone": phoneController.text.trim()
    },
  );

  var data = jsonDecode(response.body);

  if (data["success"] != true) {
    print("User not found");
    return;
  }

  String userId = data["user_id"];

  // 🔥 SAVE USER_ID
  final prefs = await SharedPreferences.getInstance();
  prefs.setString("user_id", userId);

  // 🔥 GET FCM TOKEN
  String? fcmToken = await FirebaseMessaging.instance.getToken();
  print("FCM TOKEN: $fcmToken");

  // 🔥 SEND TOKEN TO BACKEND
  if (fcmToken != null) {
  await sendTokenToServer(fcmToken);
}

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
  }*/

  Future<void> sendOtp() async {
    if (!validateInput()) return;

    setState(() => isLoading = true);

    try {
      var res = await http.post(
        Uri.parse("https://bigiluu.com/api/send-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phoneController.text.trim()}),
      );

      var data = jsonDecode(res.body);

      setState(() => isLoading = false);

      if (res.statusCode == 200 && data["success"] == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpPage(phone: "+91${phoneController.text.trim()}"),
          ),
        );
      } else {
        showError(data["message"] ?? "OTP Failed");
      }
    } catch (e) {
      setState(() => isLoading = false);
      showError("Server error / No response");
    }
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
                                        sendOtp();
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
