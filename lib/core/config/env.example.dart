// Rename or copy this file to `env.dart` and fill in your actual credentials.
class Env {
  // Supabase Configuration
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  // Cloudflare R2 Configuration
  static const String r2Endpoint = 'https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com';
  static const String r2BucketName = 'YOUR_BUCKET_NAME';
  static const String r2PublicDomain = 'https://YOUR_PUBLIC_R2_DOMAIN.r2.dev';

  // Google AdMob Configuration
  static const String admobAppId = 'YOUR_ADMOB_APP_ID';
  static const String admobInterstitialUnitId = 'YOUR_INTERSTITIAL_UNIT_ID';
  static const String admobBannerUnitId = 'YOUR_BANNER_UNIT_ID';

  // Test Ad Unit IDs (fallback for emulator / test safety if needed)
  static const String admobTestBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String admobTestInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
}
