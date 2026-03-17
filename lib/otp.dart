import 'dart:async';
import 'dart:convert';
import 'package:bigilu/home.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:sms_autofill/sms_autofill.dart'; // New import for zero-tap

class OtpPage extends StatefulWidget {
  final String phone;
  final String verificationId;

  const OtpPage({super.key, required this.phone, required this.verificationId});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> with CodeAutoFill { // Added CodeAutoFill mixin
  int seconds = 60;
  Timer? timer;
  final TextEditingController otpController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  bool isLoading = false;
  String? appSignature;

  @override
  void codeUpdated() {
    // This is called automatically when the SMS arrives!
    setState(() {
      if (code != null) {
        otpController.text = code!;
        if (otpController.text.length == 6) {
          verifyOtp(); // Auto-verify once filled
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    startTimer();
    listenForCode(); // Start listening for the SMS
    
    // Get App Signature (useful for Firebase specialized SMS)
    SmsAutoFill().getAppSignature.then((signature) {
      setState(() {
        appSignature = signature;
      });
      print("App Signature => $signature");
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

  Future<void> verifyOtp() async {
    String otp = otpController.text;

    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter complete 6-digit OTP")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      final idToken = await FirebaseAuth.instance.currentUser!.getIdToken(true);
      final res = await http.post(
        Uri.parse("https://bigiluu.com/api/login-firebase"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "idToken": idToken,
          "phoneno": widget.phone,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception("Backend login failed");
      }

      final data = jsonDecode(res.body);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("token", data["token"]);
      await prefs.setString("user_id", data["user_id"]);
      await prefs.setString("user_mobile", widget.phone);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }

    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    timer?.cancel();
    otpController.dispose();
    focusNode.dispose();
    unregisterListener(); // Stop listening when page closed
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
          // Top Center Logo
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
                filterQuality: FilterQuality.high,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 140),
                        
                        // Main OTP Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                // ignore: deprecated_member_use
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Text(
                                "OTP Verification",
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1A1A1A),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 14,
                                    // ignore: deprecated_member_use
                                    color: Colors.black.withOpacity(0.6),
                                    height: 1.5,
                                  ),
                                  children: [
                                    const TextSpan(text: "We have sent a 6-digit code to\n"),
                                    TextSpan(
                                      text: widget.phone,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),

                              // ZERO-TAP AUTOFILL SECTION
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  // 1. Visible Decorative Boxes
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: List.generate(6, (index) {
                                      String char = "";
                                      if (otpController.text.length > index) {
                                        char = otpController.text[index];
                                      }
                                      bool isCurrent = otpController.text.length == index;
                                      
                                      return Container(
                                        height: boxSize,
                                        width: boxSize,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          // ignore: deprecated_member_use
                                          color: char.isNotEmpty ? const Color(0xFFB11226).withOpacity(0.05) : Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isCurrent || char.isNotEmpty 
                                                ? const Color(0xFFB11226) 
                                                // ignore: deprecated_member_use
                                                : Colors.black.withOpacity(0.1),
                                            width: 2,
                                          ),
                                        ),
                                        child: Text(
                                          char,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFFB11226),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),

                                  // 2. Translucent REAL TextField for SMS Auto-fill
                                  Positioned.fill(
                                    child: Opacity(
                                      opacity: 0.01,
                                      child: TextField(
                                        controller: otpController,
                                        focusNode: focusNode,
                                        keyboardType: TextInputType.number,
                                        autofillHints: const [AutofillHints.oneTimeCode],
                                        enableInteractiveSelection: true,
                                        showCursor: false,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(6),
                                        ],
                                        onChanged: (val) {
                                          setState(() {});
                                          if (val.length == 6) {
                                            verifyOtp();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 32),

                              // Timer
                              Text(
                                seconds > 0 
                                  ? "Resend code in ${seconds.toString().padLeft(2, '0')}s" 
                                  : "I didn't receive a code",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  // ignore: deprecated_member_use
                                  color: Colors.black.withOpacity(0.5),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (seconds == 0)
                                TextButton(
                                  onPressed: () {
                                    startTimer();
                                  },
                                  child: const Text(
                                    "Resend Code",
                                    style: TextStyle(
                                      color: Color(0xFFB11226),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Verify Button
                        Container(
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFB11226), Color(0xFFD32F2F)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                // ignore: deprecated_member_use
                                color: const Color(0xFFB11226).withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: isLoading ? null : verifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                                    "Verify & Login",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Powered by Brand Logo
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    children: [
                      Text(
                        "POWERED BY",
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
                          height: 110,
                          width: screenWidth * 0.85,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ],
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
