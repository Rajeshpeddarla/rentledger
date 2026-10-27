import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'views/splash/splash_screen.dart';

class RentLedgerApp extends StatelessWidget {
  const RentLedgerApp({super.key});

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
            title: 'RentLedger',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
