// ignore_for_file: avoid_print, empty_catches, avoid_catches_without_on_clauses
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:climate_app/features/auth/models/user_role.dart';

Future<void> testDirectSignup() async {
  try {
    print("----- STARTING DIRECT TEST SIGNUP -----");
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: "direct_test_${DateTime.now().millisecondsSinceEpoch}@test.com",
      password: "Password123",
    );
    print("User created in Auth: ${cred.user?.uid}");

    print("Attempting to write to Firestore...");
    await FirebaseFirestore.instance
        .collection('users')
        .doc(cred.user!.uid)
        .set({
          'uid': cred.user!.uid,
          'email': cred.user!.email,
          'firstName': 'Test',
          'lastName': 'User',
          'phone': '+2348000000000',
          'state': 'Lagos',
          'lga': 'Ikeja',
          'ward': 'Ward A',
          'address': 'Test Address',
          'role': 'user', // Explicitly using 'user' string
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'isApproved': true,
          'isActive': true,
          'points': 0,
          'communityRank': 'Novice',
        });
    print("----- FIRESTORE WRITE SUCCESSFUL! -----");
  } catch (e, stack) {
    print("----- FIRESTORE WRITE FAILED! -----");
    print(e);
    print(stack);
  }
}
