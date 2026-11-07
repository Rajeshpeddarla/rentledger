import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../app.dart';
import '../../core/config/app_theme.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../main_scaffold/main_bottom_nav_screen.dart';
import '../onboarding/reset_password_screen.dart';
import '../onboarding/setup_business_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // 1-second branding display
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    if (RentLedgerApp.isPasswordRecoveryFlow) {
      RentLedgerApp.isPasswordRecoveryFlow = false;
      debugPrint('--> [SPLASH] Navigating to ResetPasswordScreen for recovery flow');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      );
      return;
    }

    final storeCubit = context.read<StoreCubit>();
    await storeCubit.initSession();

    if (!mounted) return;

    if (storeCubit.state is StoreLoaded) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainBottomNavScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupBusinessScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/logo.png',
                  width: 90,
                  height: 90,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'RentLedger',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.03,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Equipment, Item & Deposit Rental Manager',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    letterSpacing: 0.02,
                  ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
