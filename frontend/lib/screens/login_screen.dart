// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_signin_button/flutter_signin_button.dart';
import 'package:study_assistance/services/auth_service.dart';
import 'package:study_assistance/screens/dashboard_screen.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();
    final projectProvider = Provider.of<ProjectProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Welcome"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Sign in to continue',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            SignInButton(
              Buttons.GitHub,
              text: "Sign in with GitHub",
              onPressed: () async {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                // Simply call the sign-in method.
                final userCredential = await authService.signInWithGitHub();
                
                // Pop the loading indicator, regardless of success or failure.
                // The AuthWrapper will handle the navigation.
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                }

                // Optional: If it failed, show an error. The wrapper won't navigate.
                if (userCredential == null) {
                  print("Sign in failed.");
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Could not sign in with GitHub. Please try again."),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
                // If successful, the authStateChanges stream will fire, and the AuthWrapper
                // will automatically rebuild and navigate to the DashboardScreen.
                // We don't need to do anything else here.
              },
            ),

            const SizedBox(height: 20),

            // --- NEW: GUEST MODE BUTTON ---
            TextButton(
              onPressed: () {
                // 1. Set the provider to guest mode
                projectProvider.enterGuestMode();

                // 2. Navigate to the dashboard
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const DashboardScreen(),
                  ),
                );
              },
              child: const Text('Continue as Guest'),
            ),
          ],
        ),
      ),
    );
  }
}