import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
                    decoration: InputDecoration(
                      hintText: 'Search country or currency...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enter your email and password.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.errorRed,
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

    if (!mounted) return;
    final state = context.read<StoreCubit>().state;
    if (state is StoreLoaded) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainBottomNavScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCountryInfo = CountryCurrency.getCountryByName(_selectedCountry);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.storefront,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isSignInMode ? 'Welcome Back' : 'Set Up Your Store',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignInMode
                        ? 'Sign in with your linked account to restore all your cloud rental data.'
                        : 'Start tracking rentals, security deposits, and condition receipts in seconds.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 32),
                  if (!_isSignInMode) ...[
                    Text(
                      'Business / Store Name',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Apex Camera & Equipment Rentals',
                        prefixIcon: Icon(Icons.business),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter your store name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Store Country / Location',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),

                    // Custom Bottom Sheet Trigger Card Field
                    InkWell(
                      onTap: _showCountryPickerBottomSheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                selectedCountryInfo.flag,
                                style: const TextStyle(fontSize: 20),
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
                              Icons.unfold_more_rounded,
                              color: isDark ? AppColors.primaryLight : AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.primaryLight : AppColors.primary).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Currency auto-set to ${selectedCountryInfo.symbol} based on ${selectedCountryInfo.name} location.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.primaryLight : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Email Address',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'owner@store.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Password',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline),
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
                  ],
                  const SizedBox(height: 32),
                  BlocBuilder<StoreCubit, StoreState>(
                    builder: (context, state) {
                      final isLoading = state is StoreLoading;
                      return ElevatedButton(
                        onPressed: isLoading ? null : _handleSubmit,
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
                                  Text(_isSignInMode ? 'Sign In & Restore' : 'Get Started Now'),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward, size: 18),
                                ],
                              ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _isSignInMode = !_isSignInMode;
                        });
                      },
                      child: Text(
                        _isSignInMode
                            ? 'New to RentLedger? Set up a new store'
                            : 'Already have a Pro account? Sign In',
                        style: TextStyle(
                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
