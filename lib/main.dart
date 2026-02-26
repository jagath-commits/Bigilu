import 'dart:io' show Platform;
import 'package:bigilu/home.dart';
import 'package:bigilu/otp.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';


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

class MyApp extends StatelessWidget {
  final String? token;

  const MyApp({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return CupertinoApp(
        debugShowCheckedModeBanner: false,
        home: token != null ? const HomePage() : const LoginPage(),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: token != null ? const HomePage() : const LoginPage(),
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
              verificationId: verificationId,   // ✅ pass this
            ),
          )
        : MaterialPageRoute(
            builder: (_) => OtpPage(
              phone: "+91${phoneController.text.trim()}",
              verificationId: verificationId,   // ✅ pass this
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
@override
Widget build(BuildContext context) {
  final screenHeight = MediaQuery.of(context).size.height;
  final screenWidth = MediaQuery.of(context).size.width;

  return Scaffold(
    resizeToAvoidBottomInset: true,
    body: Stack(
      children: [
        // Background Image
        Positioned.fill(
          child: Image.asset(
            "assets/images/vijay1.jpg",
            fit: BoxFit.cover,
              cacheWidth: 720,
  filterQuality: FilterQuality.low,
          ),
        ),

        // Dark Overlay
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.6)),
        ),

        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.08,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [

                        const Spacer(),

                        Text(
                          "என் நெஞ்சில் குடியிருக்கும் !",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: screenWidth * 0.055,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        SizedBox(height: screenHeight * 0.05),

                        // Phone Field
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            hintText: "Enter 10-digit mobile number",
                            filled: true,
                            fillColor: Colors.yellow,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: screenHeight * 0.02,
                              horizontal: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixText: "+91 ",
                            prefixStyle: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.04),

                        // Login Button
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
                            onPressed: isLoading
                                ? null
                                : () {
                                    if (validateInput()) {
                                      sendOtpFirebase();
                                    }
                                  },
                            child: isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    "Send OTP",
                                    style: TextStyle(
                                      fontSize: screenWidth * 0.045,
                                      color: Colors.white,
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
      ],
    ),
  );
}
}
