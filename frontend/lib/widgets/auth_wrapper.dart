// lib/widgets/auth_wrapper.dart
import 'package:flutter/material.dart';
import 'package:study_assistance/screens/dashboard_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Since there is no login, we always go directly to the DashboardScreen.
    return const DashboardScreen();
  }
}