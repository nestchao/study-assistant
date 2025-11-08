// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // To handle web platform

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream to listen for authentication changes
  Stream<User?> get user => _auth.authStateChanges();

  // --- SIGN IN WITH GITHUB ---
  Future<UserCredential?> signInWithGitHub() async {
    // Create a new provider
    GithubAuthProvider githubProvider = GithubAuthProvider();

    // The process is different for web vs. mobile
    if (kIsWeb) {
      // For web, we use signInWithPopup. This is a better UX than redirecting.
      try {
        return await _auth.signInWithPopup(githubProvider);
      } on FirebaseAuthException catch (e) {
        print("Firebase Auth Exception on web: ${e.message}");
        return null;
      } catch (e) {
        print("An unknown error occurred: $e");
        return null;
      }
    } else {
      // For mobile (Android/iOS), signInWithProvider is standard.
      // This will open a webview within the app.
      try {
        return await _auth.signInWithProvider(githubProvider);
      } on FirebaseAuthException catch (e) {
        print("Firebase Auth Exception on mobile: ${e.message}");
        return null;
      } catch (e) {
        print("An unknown error occurred: $e");
        return null;
      }
    }
  }

  // --- SIGN OUT ---
  Future<void> signOut() async {
    await _auth.signOut();
  }
}