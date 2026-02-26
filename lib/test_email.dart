import 'package:flutter/material.dart';
import 'package:climate_app/core/services/email_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    debugPrint('Testing EmailService...');
    final success = await EmailService().sendVerificationCode(
      'test@cradi.local',
      '123456',
      name: 'Test User',
    );
    debugPrint('Result: $success');
  } on Exception catch (e) {
    debugPrint('Error: $e');
  }
}
