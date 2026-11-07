import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/admin_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/theme/theme_cubit.dart';
import '../admin/admin_panel_screen.dart';
import '../onboarding/setup_business_screen.dart';
import '../support/support_ticket_list_screen.dart';
import 'category_list_screen.dart';
import 'customer_directory_screen.dart';
import 'discount_list_screen.dart';
import 'edit_store_profile_screen.dart';
import 'loyalty_screen.dart';
import 'reports_screen.dart';
import 'secure_account_sheet.dart';
import 'subscription_paywall_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AdminRepository _adminRepo = AdminRepository();
  bool _enableCoupons = false;
  bool _enableLoyalty = false;

  @override
  void initState() {
    super.initState();
    _loadSystemFlags();
  }

  Future<void> _loadSystemFlags() async {
    final flags = await _adminRepo.getSystemFeatureFlags();
    if (mounted) {
      setState(() {
        _enableCoupons = flags['enable_coupons'] ?? false;
        _enableLoyalty = flags['enable_loyalty'] ?? false;
      });
    }
  }
  void _navigateToEditStoreProfile(BuildContext context, StoreModel store) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditStoreProfileScreen(store: store),
      ),
    );
  }

  void _handleSignOut(BuildContext context) {
    final storeState = context.read<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;
    final bool isSecured = store?.isAccountSecured ?? true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isSecured) {
      // Unsecured Guest Account Sign-Out Warning
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.errorRed, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Unsecured Guest Account',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have not linked an email & password to ${store?.businessName ?? "your store"}.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'If you sign out now without safeguarding your account, you will lose access to this guest account and all your inventory/lease data.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dCtx);
                _showPermanentDeletionConfirmationDialog(context, store);
              },
              child: const Text(
                'Sign Out Anyway',
                style: TextStyle(color: AppColors.errorRed, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dCtx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: isDark ? AppColors.darkCard : Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => const SecureAccountSheet(),
                );
              },
              icon: const Icon(Icons.shield_outlined, size: 16),
              label: const Text('Link Email & Save Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      );
    } else {
      // Standard Secured Account Sign-Out
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to sign out from ${store?.businessName ?? "your store"}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final storeCubit = context.read<StoreCubit>();
                Navigator.pop(dCtx);
                await storeCubit.signOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SetupBusinessScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  void _showPermanentDeletionConfirmationDialog(BuildContext context, StoreModel? store) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_outlined, color: AppColors.errorRed, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Final Warning: Delete All Data',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.errorRed),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you absolutely sure you want to sign out of ${store?.businessName ?? "this guest account"}?',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.errorRed, width: 1),
              ),
              child: const Text(
                '⚠️ All inventory items, leases, receipts, and customer records will be PERMANENTLY DELETED from our servers immediately and cannot be recovered.',
                style: TextStyle(fontSize: 11.5, color: AppColors.errorRed, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel / Keep Data', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final storeCubit = context.read<StoreCubit>();
              Navigator.pop(dCtx);
              await storeCubit.deleteGuestAccountAndSignOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SetupBusinessScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Delete All Data & Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Store Profile & Settings'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: BlocBuilder<StoreCubit, StoreState>(
        builder: (context, state) {
          if (state is! StoreLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          final store = state.store;
          final isPro = store.isPro;
          final completion = store.profileCompletionPercentage;

          return RefreshIndicator(
            onRefresh: () async {
              await context.read<StoreCubit>().initSession();
              await _loadSystemFlags();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Store Name & Completion Percentage Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: store.logoR2Url != null && store.logoR2Url!.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(store.logoR2Url!, fit: BoxFit.cover),
                                  )
                                : const Icon(Icons.store, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        store.businessName,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isPro)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.tertiaryFixed,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.tertiary)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${store.phone ?? "No store phone"} • ${store.country ?? "India"}',
                                  style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                ),
                                if (store.upiId != null && store.upiId!.isNotEmpty)
                                  Text(
                                    'UPI: ${store.upiId}',
                                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.primaryLight : AppColors.primary, fontWeight: FontWeight.w600),
                                  ),
                                if (store.ownerName != null && store.ownerName!.isNotEmpty)
                                  Text(
                                    'Owner: ${store.ownerName}',
                                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary, fontWeight: FontWeight.w500),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: (isDark ? AppColors.primaryLight : AppColors.primary).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.edit, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                            ),
                            onPressed: () => _navigateToEditStoreProfile(context, store),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_user_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                              const SizedBox(width: 6),
                              const Text('Profile Setup Progress', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Text(
                            '$completion% Complete',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isDark ? AppColors.primaryLight : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: completion / 100.0,
                          minHeight: 6,
                          backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          valueColor: AlwaysStoppedAnimation<Color>(isDark ? AppColors.primaryLight : AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStepCheck('Store Info', store.isStoreInfoComplete),
                          _buildStepCheck('UPI / QR', store.isPaymentQrComplete),
                          _buildStepCheck('Owner Info', store.isOwnerDetailsComplete),
                          _buildStepCheck('Account Secured', store.isAccountSecured),
                        ],
                      ),

                      if (!store.isStoreInfoComplete || !store.isPaymentQrComplete) ...[
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () => _navigateToEditStoreProfile(context, store),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.add_circle_outline, size: 16, color: Colors.amber.shade800),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    !store.isStoreInfoComplete
                                        ? 'Add store phone & address to complete Store Info setup.'
                                        : 'Add UPI ID or Payment QR code to complete payment setup.',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.secondary),
                              ],
                            ),
                          ),
                        ),
                      ],

                      if (!store.isAccountSecured) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                              builder: (_) => const SecureAccountSheet(),
                            );
                          },
                          icon: const Icon(Icons.shield_outlined, size: 16),
                          label: const Text('Link Email & Password to Secure Account'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
                            side: BorderSide(color: isDark ? AppColors.primaryLight : AppColors.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Theme Mode Switcher
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(isDark ? Icons.dark_mode : Icons.light_mode,
                              size: 20, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          const SizedBox(width: 8),
                          const Text('Appearance & Theme', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      BlocBuilder<ThemeCubit, ThemeMode>(
                        builder: (context, themeMode) {
                          return Row(
                            children: [
                              _buildThemeOption(
                                label: 'Light',
                                icon: Icons.light_mode_outlined,
                                isSelected: themeMode == ThemeMode.light,
                                onTap: () => context.read<ThemeCubit>().setLightMode(),
                                isDark: isDark,
                              ),
                              const SizedBox(width: 8),
                              _buildThemeOption(
                                label: 'Dark',
                                icon: Icons.dark_mode_outlined,
                                isSelected: themeMode == ThemeMode.dark,
                                onTap: () => context.read<ThemeCubit>().setDarkMode(),
                                isDark: isDark,
                              ),
                              const SizedBox(width: 8),
                              _buildThemeOption(
                                label: 'System',
                                icon: Icons.settings_brightness,
                                isSelected: themeMode == ThemeMode.system,
                                onTap: () => context.read<ThemeCubit>().setSystemMode(),
                                isDark: isDark,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Navigation Cards (Categories, Customers, Reports, Pro Paywall)
                _buildSettingsTile(
                  icon: Icons.category_outlined,
                  title: 'Equipment Categories Configuration',
                  subtitle: 'Add, edit, or remove custom equipment categories for inventory items',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CategoryListScreen()),
                    );
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                _buildSettingsTile(
                  icon: Icons.people_outline,
                  title: 'Customers Directory',
                  subtitle: 'Manage client KYC, phone numbers, and past lease records',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CustomerDirectoryScreen()),
                    );
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                if (_enableCoupons) ...[
                  _buildSettingsTile(
                    icon: Icons.discount_outlined,
                    title: 'Promotional Discounts & Vouchers',
                    subtitle: 'Configure percentage or flat rate discount coupons for categories or equipment',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DiscountListScreen()),
                      );
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                ],

                if (_enableLoyalty) ...[
                  _buildSettingsTile(
                    icon: Icons.stars_outlined,
                    title: 'Customer Loyalty Program & Rewards',
                    subtitle: 'Set earning rates, points redemption value, and 30-day locked expiry periods',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoyaltyScreen()),
                      );
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                ],

                _buildSettingsTile(
                  icon: Icons.bar_chart_outlined,
                  title: 'Weekly & Monthly Financial Reports',
                  subtitle: 'Audit revenue, rental volume, and export PDF/CSV spreadsheets',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReportsScreen()),
                    );
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                _buildSettingsTile(
                  icon: Icons.workspace_premium_outlined,
                  title: isPro ? 'RentLedger Pro Active' : 'Upgrade to RentLedger Pro',
                  subtitle: isPro
                      ? 'Unlimited items & leases, custom logo & zero watermarks'
                      : 'Unlock unlimited fleet, ad-free experience & PDF exports',
                  color: AppColors.tertiaryAmber,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SubscriptionPaywallScreen()),
                    );
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                _buildSettingsTile(
                  icon: Icons.support_agent_outlined,
                  title: 'Support & Help Center',
                  subtitle: 'Submit support tickets with screenshots and track issue status',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SupportTicketListScreen()),
                    );
                  },
                  isDark: isDark,
                ),

                const SizedBox(height: 16),

                Builder(
                  builder: (ctx) {
                    final currentUserEmail = Supabase.instance.client.auth.currentUser?.email?.toLowerCase();
                    final isSuperAdmin = (currentUserEmail == 'varunsai428@gmail.com') ||
                        (store.email?.toLowerCase() == 'varunsai428@gmail.com') ||
                        (store.ownerEmail?.toLowerCase() == 'varunsai428@gmail.com');

                    if (!isSuperAdmin) return const SizedBox.shrink();

                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [const Color(0xFF1E3A8A), const Color(0xFF0F172A)]
                                  : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.admin_panel_settings, color: Color(0xFF2563EB), size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Super Admin Control Panel',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'System metrics, store management, coupon/loyalty viewer & support ticket resolution center.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E3A8A),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.dashboard_outlined, size: 18),
                                  label: const Text('Open Admin Panel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  onPressed: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                                    );
                                    _loadSystemFlags();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 20),

                // Sign Out Tile
                InkWell(
                  onTap: () => _handleSignOut(context),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sign Out from Store',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Safely log out of your current rental store session',
                                style: TextStyle(fontSize: 11, color: AppColors.secondary),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 20, color: Colors.redAccent),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    ),
  );
}

  Widget _buildStepCheck(String label, bool isDone) {
    return Column(
      children: [
        Icon(isDone ? Icons.check_circle : Icons.circle_outlined, size: 16, color: isDone ? AppColors.primaryLight : AppColors.secondary),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : (isDark ? Colors.white : AppColors.slateNavy)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : (isDark ? Colors.white : AppColors.slateNavy),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (color ?? AppColors.primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color ?? AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}
