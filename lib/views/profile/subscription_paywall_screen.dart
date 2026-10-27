import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_theme.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/subscription/subscription_cubit.dart';
import 'secure_account_sheet.dart';

class SubscriptionPaywallScreen extends StatefulWidget {
  const SubscriptionPaywallScreen({super.key});

  @override
  State<SubscriptionPaywallScreen> createState() => _SubscriptionPaywallScreenState();
}

class _SubscriptionPaywallScreenState extends State<SubscriptionPaywallScreen> {
  bool _isAnnual = true;

  void _handleUpgrade() {
    final storeState = context.read<StoreCubit>().state;
    final isAnonymous = storeState is StoreLoaded && !storeState.store.isAccountSecured;

    if (isAnonymous) {
      // Enforce Section 5.2 Rule: "Secure Account FIRST, Then Upgrade"
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SecureAccountSheet(
          onSuccess: () => _proceedWithPurchase(),
        ),
      );
    } else {
      _proceedWithPurchase();
    }
  }

  void _proceedWithPurchase() async {
    final subscriptionCubit = context.read<SubscriptionCubit>();
    final storeCubit = context.read<StoreCubit>();
    final tier = _isAnnual ? 'pro_annual' : 'pro_monthly';
    await subscriptionCubit.upgradeToTier(tier);
    await storeCubit.initSession();

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Welcome to RentLedger Pro (${_isAnnual ? "Annual" : "Monthly"})!',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final isPro = storeState is StoreLoaded && storeState.store.isPro;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Upgrade to Pro'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // Crown / Gold Badge
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.tertiaryFixed,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.tertiaryAmber.withValues(alpha: 0.3), blurRadius: 16),
                ],
              ),
              child: const Icon(Icons.workspace_premium, color: AppColors.tertiary, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              'Supercharge Your Rental Fleet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Unlimited items, custom branding, zero watermarks & PDF reports.',
              style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            // Billing Cycle Toggle (Monthly vs Annual)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightSurfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _isAnnual = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: !_isAnnual ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Monthly (₹249)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: !_isAnnual ? Colors.white : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _isAnnual = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _isAnnual ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Annual (₹1,999)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _isAnnual ? Colors.white : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.tertiaryFixed,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('SAVE 33%', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.tertiary)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Feature Comparison Matrix
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                children: [
                  _buildMatrixRow('Active Items Fleet', '10 Items', 'UNLIMITED', true, isDark),
                  const Divider(),
                  _buildMatrixRow('Monthly Leases Quota', '15 Leases/mo', 'UNLIMITED', true, isDark),
                  const Divider(),
                  _buildMatrixRow('Receipt PDF Branding', 'RentLedger Tag', 'Custom Store Logo', true, isDark),
                  const Divider(),
                  _buildMatrixRow('Condition Photos in PDF', 'Excluded', 'Embedded WebP', true, isDark),
                  const Divider(),
                  _buildMatrixRow('UPI Checkout QR', 'Static Image', 'Dynamic Auto-Amount', true, isDark),
                  const Divider(),
                  _buildMatrixRow('Financial Reports Export', 'Screen Only', 'PDF & Excel (CSV)', true, isDark),
                  const Divider(),
                  _buildMatrixRow('Ad Experience', 'Banner & Video', '100% Ad-Free', true, isDark),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (isPro)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryLight),
                ),
                child: const Center(
                  child: Text(
                    'You are currently on RentLedger Pro!',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                  ),
                ),
              )
            else
              ElevatedButton(
                onPressed: _handleUpgrade,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _isAnnual ? 'Upgrade to Pro Annual (₹1,999/yr)' : 'Upgrade to Pro Monthly (₹249/mo)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Secure Google Play Billing. Cancel anytime.',
              style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMatrixRow(String feature, String free, String pro, bool isHighlighted, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              feature,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              free,
              style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              pro,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.primaryLight : AppColors.primary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
