import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:bigilu/profile.dart';
import 'package:sms_autofill/sms_autofill.dart';

class OtpPage extends StatefulWidget {
  final String phone;

  const OtpPage({super.key, required this.phone});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> with CodeAutoFill {
  int seconds = 60;
  Timer? timer;
  final TextEditingController otpController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  bool isLoading = false;
  String? appSignature;
  bool isVerifying = false;

  @override
  void codeUpdated() {
    setState(() {
      if (code != null) {
        otpController.text = code!;
      }
    });
  }

  @override
  void initState() {
    super.initState();

    startTimer();
    listenForCode();

    SmsAutoFill().getAppSignature.then((signature) {
      setState(() {
        appSignature = signature;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
    });
  }

  void startTimer() {
    timer?.cancel();
    setState(() {
      seconds = 60;
    });
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (seconds > 0) {
        setState(() => seconds--);
      } else {
        t.cancel();
      }
    });
  }

  // ✅ UPDATED VERIFY (NO FIREBASE)
  Future<void> verifyOtp() async {
    if (isVerifying) return;
    isVerifying = true;

    String otp = otpController.text;

    if (otp.length != 6) {
      isVerifying = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter complete 6-digit OTP")),
      );
      return;
    }

    if (seconds == 0) {
      isVerifying = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OTP expired. Please resend.")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final res = await http.post(
        Uri.parse("https://bigiluu.com/api/verify-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": widget.phone,
          "otp": otp,
          "username": "New User", // Passed to avoid backend NULL error for new registrations
        }),
      );

      final data = jsonDecode(res.body);

      if (data["success"] != true) {
        throw Exception(data["message"]);
      }

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString("token", data["token"]);
      await prefs.setString("user_id", data["user_id"]);
      await prefs.setString("user_mobile", widget.phone);

      // 🔥 FCM TOKEN (UNCHANGED)
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        print("FCM Token Error: $e");
      }

      if (data["user_id"] != null && fcmToken != null) {
        await http.post(
          Uri.parse("https://bigiluu.com/api/posts/save-token"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "user_id": data["user_id"],
            "fcm_token": fcmToken
          }),
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EditProfilePage(userId: data["user_id"]),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }

    isVerifying = false;
    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    timer?.cancel();
    otpController.dispose();
    focusNode.dispose();
    unregisterListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    double boxSize = (screenWidth - 140) / 6;
    if (boxSize > 50) boxSize = 50;
    if (boxSize < 35) boxSize = 35;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned(
            top: MediaQuery.of(context).padding.top + 30,
            left: 0,
            right: 0,
            child: Center(
              child: Image.asset(
                "assets/images/bigilu_logo21.png",
                height: 90,
                width: 240,
                fit: BoxFit.contain,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 140),

                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 32, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                "OTP Verification",
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),

                              Text(widget.phone),

                              const SizedBox(height: 32),

                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: List.generate(6, (index) {
                                      String char = "";
                                      if (otpController.text.length > index) {
                                        char = otpController.text[index];
                                      }

                                      return Container(
                                        height: boxSize,
                                        width: boxSize,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          border: Border.all(),
                                        ),
                                        child: Text(char),
                                      );
                                    }),
                                  ),
                                  Positioned.fill(
                                    child: Opacity(
                                      opacity: 0.01,
                                      child: TextField(
                                        controller: otpController,
                                        focusNode: focusNode,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(6),
                                        ],
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 32),

                              Text(seconds > 0
                                  ? "Resend in $seconds s"
                                  : "Resend OTP"),

                              if (seconds == 0)
                                TextButton(
                                  onPressed: () async {
                                    startTimer();

                                    await http.post(
                                      Uri.parse(
                                          "https://bigiluu.com/api/send-otp"),
                                      headers: {
                                        "Content-Type": "application/json"
                                      },
                                      body: jsonEncode({
                                        "phone": widget.phone
                                            .replaceAll("+91", "")
                                      }),
                                    );
                                  },
                                  child: const Text("Resend Code"),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        ElevatedButton(
                          onPressed: isLoading ? null : verifyOtp,
                          child: isLoading
                              ? const CircularProgressIndicator()
                              : const Text("Verify & Login"),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}