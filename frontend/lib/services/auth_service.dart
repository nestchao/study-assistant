// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream will always report null (logged out), which is fine.
  Stream<User?> get user => _auth.authStateChanges();

  // Sign out does nothing but is kept to prevent breaking other parts of the app.
  Future<void> signOut() async {
    // In a no-auth app, this does nothing.
    return;
  }
}