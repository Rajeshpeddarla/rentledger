import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_theme.dart';
import '../../core/utils/country_currency.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../main_scaffold/main_bottom_nav_screen.dart';

class SetupBusinessScreen extends StatefulWidget {
  const SetupBusinessScreen({super.key});

  @override
  State<SetupBusinessScreen> createState() => _SetupBusinessScreenState();
}

class _SetupBusinessScreenState extends State<SetupBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Apex Rentals & Tools');
  String _selectedCountry = 'India';

  bool _isSignInMode = false;
  bool _obscurePassword = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-detect country based on system locale
    try {
      final locale = Platform.localeName;
      if (locale.contains('US')) {
        _selectedCountry = 'United States';
      } else if (locale.contains('GB')) {
        _selectedCountry = 'United Kingdom';
      } else if (locale.contains('CA')) {
        _selectedCountry = 'Canada';
      } else if (locale.contains('AU')) {
        _selectedCountry = 'Australia';
      } else if (locale.contains('DE')) {
        _selectedCountry = 'Germany';
      } else if (locale.contains('FR')) {
        _selectedCountry = 'France';
      } else if (locale.contains('AE')) {
        _selectedCountry = 'United Arab Emirates';
      } else if (locale.contains('SG')) {
        _selectedCountry = 'Singapore';
      } else if (locale.contains('IN')) {
        _selectedCountry = 'India';
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showCountryPickerBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            final filteredCountries = CountryCurrency.countries.where((c) {
              final q = searchQuery.toLowerCase();
              return c.name.toLowerCase().contains(q) ||
                  c.code.toLowerCase().contains(q) ||
                  c.symbol.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Store Location & Currency',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose your country to automatically set your default rental currency.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Search Field
                  TextField(
                    onChanged: (val) {
                      setBottomSheetState(() {
                        searchQuery = val;
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Search country or currency...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Country Cards List
                  Expanded(
                    child: filteredCountries.isEmpty
                        ? const Center(child: Text('No matching countries found.'))
                        : ListView.separated(
                            itemCount: filteredCountries.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 10),
                            itemBuilder: (ctx, index) {
                              final c = filteredCountries[index];
                              final isSelected = c.name.toLowerCase() == _selectedCountry.toLowerCase();

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedCountry = c.name;
                                  });
                                  Navigator.pop(ctx);
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDark ? AppColors.primaryLight.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.08))
                                        : (isDark ? AppColors.darkCard : Colors.white),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? (isDark ? AppColors.primaryLight : AppColors.primary)
                                          : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          c.flag,
                                          style: const TextStyle(fontSize: 24),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.name,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Currency: ${c.symbol} (${c.code})',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isSelected
                                                    ? (isDark ? AppColors.primaryLight : AppColors.primary)
                                                    : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle,
                                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                                          size: 22,
                                        )
                                      else
                                        Icon(
                                          Icons.radio_button_unchecked,
                                          color: isDark ? AppColors.darkBorder : Colors.grey.shade400,
                                          size: 22,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _handleSubmit() async {
    if (_isSignInMode) {
      if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Please enter your email and password.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
      await context.read<StoreCubit>().signInExisting(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
    } else {
      if (!_formKey.currentState!.validate()) return;
      final derivedCurrency = CountryCurrency.getCurrencySymbolForCountry(_selectedCountry);
      await context.read<StoreCubit>().setupBusiness(
            businessName: _nameController.text.trim(),
            currencySymbol: derivedCurrency,
            country: _selectedCountry,
          );
    }
  }

  void _showForgotPasswordDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emailResetController = TextEditingController(text: _emailController.text.trim());
    bool isResetting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.lock_reset_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Forgot Password?',
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
                    'Enter your registered email address and we will send you a password reset link.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailResetController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.secondary)),
                ),
                ElevatedButton(
                  onPressed: isResetting
                      ? null
                      : () async {
                          final email = emailResetController.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a valid email address'),
                                backgroundColor: AppColors.errorRed,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isResetting = true);

                          try {
                            await Supabase.instance.client.auth.resetPasswordForEmail(
                              email,
                              redirectTo: 'io.supabase.rentledger://reset-password',
                            );

                            if (!mounted) return;
                            Navigator.pop(dialogCtx);

                            showDialog(
                              context: context,
                              builder: (alertCtx) => AlertDialog(
                                backgroundColor: isDark ? AppColors.darkCard : Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.mark_email_read_outlined, color: AppColors.primary),
                                    SizedBox(width: 8),
                                    Text('Reset Email Sent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: Text(
                                  'A password reset link has been sent to $email. Please check your inbox and tap the link to reset your password.',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                actions: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                    onPressed: () => Navigator.pop(alertCtx),
                                    child: const Text('OK', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error sending reset email: $e'),
                                backgroundColor: AppColors.errorRed,
                              ),
                            );
                          } finally {
                            setDialogState(() => isResetting = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isResetting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                        )
                      : const Text('Send Reset Link', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCountryInfo = CountryCurrency.getCountryByName(_selectedCountry);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : const Color(0xFFEFF7F4),
      body: BlocListener<StoreCubit, StoreState>(
        listener: (context, state) {
          if (state is StoreError) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            String msg = state.message;
            if (msg.contains('Invalid login credentials') || msg.contains('invalid_credentials')) {
              msg = 'Invalid email or wrong password. Please try again.';
            } else if (msg.contains('Sign in failed:')) {
              msg = msg.replaceFirst('Sign in failed:', '').trim();
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        msg,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.red.shade700,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 4),
              ),
            );
          } else if (state is StoreLoaded) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainBottomNavScreen()),
            );
          }
        },
        child: Stack(
          children: [
            // 1. Top Right Background Light Green Curves
            if (!isDark)
              Positioned(
                top: 0,
                right: 0,
                width: MediaQuery.of(context).size.width * 0.75,
                height: 280,
                child: CustomPaint(
                  painter: TopCurvesPainter(),
                ),
              ),

            // 2. Bottom Wave Curves
            if (!isDark)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 140,
                child: CustomPaint(
                  painter: BottomWavesPainter(),
                ),
              ),

            // 3. Main Scrollable Screen Content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Header Section: Logo + Store Graphic + Title
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Logo Box
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.08),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.asset(
                                        'assets/logo.png',
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Title with underline accent
                                  RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        color: isDark ? Colors.white : const Color(0xFF0F2620),
                                        height: 1.15,
                                      ),
                                      children: [
                                        TextSpan(text: _isSignInMode ? 'Welcome ' : 'Set Up Your\n'),
                                        TextSpan(
                                          text: _isSignInMode ? 'Back' : 'Store',
                                          style: const TextStyle(
                                            color: Color(0xFF0B664D),
                                            decoration: TextDecoration.underline,
                                            decorationColor: Color(0xFF0B664D),
                                            decorationThickness: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _isSignInMode
                                        ? 'Sign in with your linked account to restore all your cloud rental data.'
                                        : 'Start tracking rentals, security deposits, and condition receipts in seconds.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? AppColors.darkOnSurfaceVariant : const Color(0xFF4A605A),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Storefront Graphic Image touching the right screen edge
                            Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Transform.translate(
                                  offset: const Offset(20, 0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                                      child: Image.asset(
                                        'assets/setupstore.jpeg',
                                        height: 140,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // 3 Feature Highlight Cards Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildFeatureCard(
                                icon: Icons.calendar_today_outlined,
                                title: 'Track',
                                subtitle: 'Rentals',
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildFeatureCard(
                                icon: Icons.shield_outlined,
                                title: 'Manage',
                                subtitle: 'Deposits',
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildFeatureCard(
                                icon: Icons.assignment_outlined,
                                title: 'Condition',
                                subtitle: 'Receipts',
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Form Container Card (Elevated White Box)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? AppColors.darkBorder : Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!_isSignInMode) ...[
                                // Field 1: Business / Store Name
                                Row(
                                  children: [
                                    Icon(Icons.storefront_outlined, size: 18, color: isDark ? AppColors.primaryLight : const Color(0xFF0B664D)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Business / Store Name',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F2620),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: InputDecoration(
                                    hintText: 'Apex Rentals & Tools',
                                    prefixIcon: const Icon(Icons.storefront_outlined),
                                    fillColor: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF7FAFA),
                                    filled: true,
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) {
                                      return 'Please enter your store name';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 18),

                                // Field 2: Store Country / Location
                                Row(
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 18, color: isDark ? AppColors.primaryLight : const Color(0xFF0B664D)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Store Country / Location',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F2620),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Custom Country Selector Card Field
                                InkWell(
                                  onTap: _showCountryPickerBottomSheet,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF7FAFA),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isDark ? AppColors.darkCard : Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: isDark ? AppColors.darkBorder : Colors.grey.shade200),
                                          ),
                                          child: Text(
                                            selectedCountryInfo.flag,
                                            style: const TextStyle(fontSize: 22),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                selectedCountryInfo.name,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Default Currency: ${selectedCountryInfo.symbol} (${selectedCountryInfo.code})',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.keyboard_arrow_down,
                                          color: isDark ? AppColors.primaryLight : const Color(0xFF0B664D),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // Info Banner
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F6F1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFC7EBDD)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline, size: 16, color: Color(0xFF0B664D)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Currency will auto-set to ${selectedCountryInfo.symbol} based on your location.',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF0B664D),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                // Sign In Mode Form
                                Row(
                                  children: [
                                    Icon(Icons.email_outlined, size: 18, color: isDark ? AppColors.primaryLight : const Color(0xFF0B664D)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Email Address',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F2620),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    hintText: 'owner@store.com',
                                    prefixIcon: const Icon(Icons.email_outlined),
                                    fillColor: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF7FAFA),
                                    filled: true,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Icon(Icons.lock_outline, size: 18, color: isDark ? AppColors.primaryLight : const Color(0xFF0B664D)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Password',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F2620),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    fillColor: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF7FAFA),
                                    filled: true,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _showForgotPasswordDialog,
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: Color(0xFF0B664D),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),

                              // Submit Action Button
                              BlocBuilder<StoreCubit, StoreState>(
                                builder: (context, state) {
                                  final isLoading = state is StoreLoading;
                                  return SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: isLoading ? null : _handleSubmit,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0B664D),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  _isSignInMode ? 'Sign In & Restore' : 'Get Started Now',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                                              ],
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Bottom Account Toggle Text
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isSignInMode = !_isSignInMode;
                              });
                            },
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? AppColors.darkOnSurfaceVariant : const Color(0xFF4A605A),
                                ),
                                children: [
                                  TextSpan(
                                    text: _isSignInMode
                                        ? 'Need to set up a new store? '
                                        : 'Already have a Pro account? ',
                                  ),
                                  TextSpan(
                                    text: _isSignInMode ? 'Create Store' : 'Sign In',
                                    style: const TextStyle(
                                      color: Color(0xFF0B664D),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : const Color(0xFFEBF7F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFD4EFE4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceLow : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFCBEBDC)),
            ),
            child: Icon(
              icon,
              size: 16,
              color: const Color(0xFF0B664D),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F2620),
                    height: 1.1,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F2620),
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter for Top-Right Light Green Organic Background Curves
class TopCurvesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = const Color(0xFFE1F5EC).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(size.width * 0.1, 0);
    path1.quadraticBezierTo(size.width * 0.4, size.height * 0.5, size.width, size.height * 0.85);
    path1.lineTo(size.width, 0);
    path1.close();
    canvas.drawPath(path1, paint1);

    final paint2 = Paint()
      ..color = const Color(0xFFCDEDE0).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(size.width * 0.35, 0);
    path2.quadraticBezierTo(size.width * 0.65, size.height * 0.7, size.width, size.height * 0.95);
    path2.lineTo(size.width, 0);
    path2.close();
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// CustomPainter for Bottom Light Green Wave Curves below Sign In text
class BottomWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = const Color(0xFFC7EBDD).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.4);
    path1.quadraticBezierTo(size.width * 0.5, size.height * 0.05, size.width, size.height * 0.35);
    path1.lineTo(size.width, size.height);
    path1.lineTo(0, size.height);
    path1.close();
    canvas.drawPath(path1, paint1);

    final paint2 = Paint()
      ..color = const Color(0xFF81D7B1).withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(0, size.height * 0.65);
    path2.quadraticBezierTo(size.width * 0.45, size.height * 0.3, size.width, size.height * 0.55);
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
