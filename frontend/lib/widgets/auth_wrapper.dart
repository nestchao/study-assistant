// lib/widgets/auth_wrapper.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:study_assistance/screens/dashboard_screen.dart';
import 'package:study_assistance/screens/login_screen.dart';
import 'package:study_assistance/services/auth_service.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // We can use a StreamProvider or listen to the stream directly.
    // Here we'll create the AuthService instance and listen.
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.user, // <-- This is the single source of truth
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final User? user = snapshot.data;
          // If user is null, show LoginScreen.
          // If user is not null, show DashboardScreen.
          return user == null ? const LoginScreen() : const DashboardScreen();
        }
        // While waiting for the first auth state, show a loading screen.
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}