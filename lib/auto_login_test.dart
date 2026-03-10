import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/services/security_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SecurityService().initializePinning();
  await Firebase.initializeApp();
  await RemoteConfigService().initialize();

  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text("Testing login..."))),
    ),
  );

  try {
    debugPrint("--------------------------------");
    debugPrint("ATTEMPTING FIREBASE LOGIN HEADLESS");
    debugPrint("--------------------------------");
    final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: "steviekusu@gmail.com",
      password: "12345Gg!",
    );
    debugPrint("SUCCESS: Logged in as ${cred.user?.uid}");
  } on Exception catch (e) {
    debugPrint("================ FATAL ERROR ================");
    debugPrint(e.toString());
    debugPrint("=============================================");
  }
}
