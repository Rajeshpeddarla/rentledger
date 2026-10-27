import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  User? get currentUser => client.auth.currentUser;
  Session? get currentSession => client.auth.currentSession;
  bool get isAuthenticated => currentUser != null;
  bool get isAnonymous => currentUser?.isAnonymous ?? true;

  /// Initializes Supabase with the configured Project URL & Anon Key
  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
      );
      debugPrint('Supabase initialized successfully');
    } catch (e) {
      debugPrint('Supabase initialization warning/error: $e');
    }
  }

  /// Zero-friction anonymous sign in for first launch
  Future<AuthResponse> signInAnonymously() async {
    try {
      final res = await client.auth.signInAnonymously();
      return res;
    } catch (e) {
      debugPrint('Error signing in anonymously: $e');
      rethrow;
    }
  }

  /// Secure account by linking email & password to current user
  /// Keeps the exact same auth.uid()!
  Future<UserResponse> linkEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final res = await client.auth.updateUser(
        UserAttributes(
          email: email,
          password: password,
        ),
      );
      return res;
    } catch (e) {
      debugPrint('Error linking email/password: $e');
      rethrow;
    }
  }

  /// Sign in existing permanent user
  Future<AuthResponse> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await client.auth.signOut();
  }
}
