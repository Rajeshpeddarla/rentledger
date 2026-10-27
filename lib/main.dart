import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Supabase
  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    debugPrint('Supabase initialized with URL: ${Env.supabaseUrl}');
  } catch (e) {
    debugPrint('Supabase init warning: $e');
  }

  // 2. Initialize Google Mobile Ads
  try {
    await MobileAds.instance.initialize();
    debugPrint('Google Mobile Ads initialized');
  } catch (e) {
    debugPrint('AdMob init warning: $e');
  }

  // 3. Launch App
  runApp(const RentLedgerApp());
}
