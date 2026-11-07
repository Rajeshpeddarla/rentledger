import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_theme.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/discount_repository.dart';
import 'data/repositories/inventory_repository.dart';
import 'data/repositories/lease_repository.dart';
import 'data/repositories/store_repository.dart';
import 'viewmodels/auth_store/store_cubit.dart';
import 'viewmodels/category/category_cubit.dart';
import 'viewmodels/customer/customer_cubit.dart';
import 'viewmodels/discount/discount_cubit.dart';
import 'viewmodels/inventory/inventory_cubit.dart';
import 'viewmodels/lease/lease_cubit.dart';
import 'viewmodels/subscription/subscription_cubit.dart';
import 'viewmodels/theme/theme_cubit.dart';
import 'views/onboarding/reset_password_screen.dart';
import 'views/splash/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class RentLedgerApp extends StatefulWidget {
  static bool isPasswordRecoveryFlow = false;

  const RentLedgerApp({super.key});

  @override
  State<RentLedgerApp> createState() => _RentLedgerAppState();
}

class _RentLedgerAppState extends State<RentLedgerApp> {
  @override
  void initState() {
    super.initState();
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) {
          final AuthChangeEvent event = data.event;
          debugPrint('--> [AUTH EVENT] AuthStateChanged: $event');
          if (event == AuthChangeEvent.passwordRecovery) {
            RentLedgerApp.isPasswordRecoveryFlow = true;
            debugPrint('--> [AUTH RECOVERY] Password recovery mode activated!');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              navigatorKey.currentState?.push(
                MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
              );
            });
          }
        },
        onError: (err) {
          debugPrint('--> [AUTH STREAM ERROR] $err');
          if (err.toString().contains('otp_expired') ||
              err.toString().contains('access_denied') ||
              err.toString().contains('expired')) {
            RentLedgerApp.isPasswordRecoveryFlow = false;
            final ctx = navigatorKey.currentContext;
            if (ctx != null) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text(
                    'The password reset link has expired or is invalid. Please request a new link.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: AppColors.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Auth state listener error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Instantiating repositories
    final storeRepo = StoreRepository();
    final leaseRepo = LeaseRepository();
    final inventoryRepo = InventoryRepository(leaseRepo);
    final customerRepo = CustomerRepository();
    final categoryRepo = CategoryRepository();
    final discountRepo = DiscountRepository();

    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        BlocProvider<StoreCubit>(create: (_) => StoreCubit(storeRepo)),
        BlocProvider<InventoryCubit>(create: (_) => InventoryCubit(inventoryRepo)),
        BlocProvider<LeaseCubit>(create: (_) => LeaseCubit(leaseRepo)),
        BlocProvider<CustomerCubit>(create: (_) => CustomerCubit(customerRepo)),
        BlocProvider<SubscriptionCubit>(create: (_) => SubscriptionCubit(storeRepo)),
        BlocProvider<CategoryCubit>(create: (_) => CategoryCubit(categoryRepo)..loadCategories()),
        BlocProvider<DiscountCubit>(create: (_) => DiscountCubit(discountRepo)..loadDiscounts()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'RentLedger',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: const SplashScreen(),
            onGenerateRoute: (settings) {
              final name = settings.name ?? '';
              if (name.contains('error=') ||
                  name.contains('otp_expired') ||
                  name.contains('access_denied')) {
                debugPrint('--> [DEEP LINK ROUTE INTERCEPTED ERROR] $name');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final ctx = navigatorKey.currentContext;
                  if (ctx != null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'The password reset link has expired or is invalid. Please request a new link.',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: AppColors.errorRed,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                });
                return MaterialPageRoute(builder: (_) => const SplashScreen());
              }
              return null;
            },
            onUnknownRoute: (settings) {
              return MaterialPageRoute(builder: (_) => const SplashScreen());
            },
          );
        },
      ),
    );
  }
}
