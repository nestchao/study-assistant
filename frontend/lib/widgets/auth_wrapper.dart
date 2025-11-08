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
      stream: authService.user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show a loading spinner while checking auth state
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData) {
          // If the snapshot has data, it means a user is logged in
          return const DashboardScreen();
        } else {
          // If no data, show the login screen
          return const LoginScreen();
        }
      },
    );
  }
}