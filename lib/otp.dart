import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:bigilu/home.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';




class OtpPage extends StatefulWidget {
  final String phone;
  final String verificationId;

  const OtpPage({
    super.key,
    required this.phone,
    required this.verificationId,
  });


  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  int seconds = 60;
  Timer? timer;
  final List<TextEditingController> controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());

  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    startTimer();
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
  String otp = controllers.map((e) => e.text).join();

  if (otp.length != 6) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Enter complete 6-digit OTP")),
    );
    return;
  }

  setState(() => isLoading = true);

  try {
    // ✅ 1. Verify OTP with Firebase
    final credential = PhoneAuthProvider.credential(
      verificationId: widget.verificationId,
      smsCode: otp,
    );

    await FirebaseAuth.instance.signInWithCredential(credential);

    // ✅ 2. Get Firebase ID token
    final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();

    // ✅ 3. Call your backend to get JWT
    final res = await http.post(
      Uri.parse("http://192.168.29.182:3000/api/login-firebase"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "idToken": idToken,
        "phoneno": widget.phone, // already has +91
      }),
    );

    if (res.statusCode != 200) {
      throw Exception("Backend login failed");
    }

    final data = jsonDecode(res.body);

    // ✅ 4. Save JWT locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("token", data["token"]);
    await prefs.setString("user_id", data["user_id"]);
    await prefs.setString("user_mobile", widget.phone);

    // ✅ 5. Navigate to Home
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }  catch (e) {
  print("OTP VERIFY ERROR => $e");   // 👈 Console-la exact error varum

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.toString())),  // 👈 UI-la exact error varum
  );
}


  setState(() => isLoading = false);
}





  @override
  void dispose() {
    timer?.cancel();
    for (var c in controllers) c.dispose();
    for (var f in focusNodes) f.dispose();
    super.dispose();
  }
@override
Widget build(BuildContext context) {
  final screenHeight = MediaQuery.of(context).size.height;
  final screenWidth = MediaQuery.of(context).size.width;

  return Scaffold(
    resizeToAvoidBottomInset: true,
    body: Stack(
      children: [
        // Background
        Positioned.fill(
          child: Image.asset(
            "assets/images/vijay1.jpg",
            fit: BoxFit.cover,
          ),
        ),

        // Dark overlay
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.5),
          ),
        ),

        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [

                        const Spacer(),

                        const Text(
                          "Enter OTP",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 10),

                        const Text(
                          "We have sent a verification code to your mobile",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.04),

                        // OTP Boxes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (index) {
                            return Container(
                              height: screenWidth * 0.12,
                              width: screenWidth * 0.12,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  )
                                ],
                              ),
                              child: TextField(
                                controller: controllers[index],
                                focusNode: focusNodes[index],
                                keyboardType: TextInputType.number,
                                maxLength: 1,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: screenWidth * 0.06,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  counterText: '',
                                  border: InputBorder.none,
                                ),
                                onChanged: (value) {
                                  if (value.isNotEmpty && index < 5) {
                                    focusNodes[index + 1].requestFocus();
                                  } else if (value.isEmpty && index > 0) {
                                    focusNodes[index - 1].requestFocus();
                                  }
                                },
                              ),
                            );
                          }),
                        ),

                        SizedBox(height: screenHeight * 0.03),

                        // Timer
                        Text(
                          "00:${seconds.toString().padLeft(2, '0')}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.yellowAccent,
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.04),

                        // Verify Button
                        SizedBox(
                          width: double.infinity,
                          height: screenHeight * 0.065,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB11226),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: isLoading ? null : verifyOtp,
                            child: isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    "Verify OTP",
                                    style: TextStyle(
                                      fontSize: screenWidth * 0.045,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.02),

                        // Resend
                        TextButton(
                          onPressed: seconds == 0
                              ? () async {
                                  startTimer();

                                  await FirebaseAuth.instance.verifyPhoneNumber(
                                    phoneNumber: widget.phone,
                                    verificationCompleted: (credential) {},
                                    verificationFailed: (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              e.message ?? "Resend failed"),
                                        ),
                                      );
                                    },
                                    codeSent:
                                        (newVerificationId, resendToken) {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => OtpPage(
                                            phone: widget.phone,
                                            verificationId:
                                                newVerificationId,
                                          ),
                                        ),
                                      );
                                    },
                                    codeAutoRetrievalTimeout:
                                        (verificationId) {},
                                  );
                                }
                              : null,
                          child: Text(
                            "Resend OTP",
                            style: TextStyle(
                              color: seconds == 0
                                  ? Colors.white
                                  : Colors.white38,
                              fontSize: 16,
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
      ],
    ),
  );
}
}
