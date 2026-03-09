// ignore_for_file: avoid_print, empty_catches, avoid_catches_without_on_clauses
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets('Directly write to Firestore', (WidgetTester tester) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    print("--- Running test direct signup ---");
    try {
      final cred = await FirebaseAuth.instance
          .signInAnonymously(); // use anonymous for easy test
      print("User created in Auth: ${cred.user?.uid}");
      await FirebaseFirestore.instance
          .collection("users")
          .doc(cred.user!.uid)
          .set({
            "uid": cred.user!.uid,
            "email": "anon@test.com",
            "firstName": "Test",
            "lastName": "User",
            "phone": "+2348000000000",
            "state": "Lagos",
            "lga": "Ikeja",
            "ward": "Ward A",
            "address": "Test Address",
            "role": "user",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "isApproved": true,
            "isActive": true,
            "points": 0,
            "communityRank": "Novice",
          });
      print("--- FIRESTORE WRITE SUCCESSFUL! ---");
    } catch (e, stack) {
      print("--- FIRESTORE WRITE FAILED! ---");
      print(e);
      print(stack);
    }
  });
}
