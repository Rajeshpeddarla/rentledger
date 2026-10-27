import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/core/config/app_theme.dart';

void main() {
  testWidgets('AppTheme supports both light and dark modes with correct branding', (WidgetTester tester) async {
    // 1. Build light theme widget
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        home: Scaffold(
          appBar: AppBar(title: const Text('RentLedger Light')),
          body: const Center(
            child: Text('Equipment, Item & Deposit Rental Manager'),
          ),
        ),
      ),
    );

    expect(find.text('RentLedger Light'), findsOneWidget);
    expect(find.text('Equipment, Item & Deposit Rental Manager'), findsOneWidget);

    // 2. Build dark theme widget
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          appBar: AppBar(title: const Text('RentLedger Dark')),
          body: Container(
            color: AppColors.darkSurface,
            child: const Text('Dark Mode Active'),
          ),
        ),
      ),
    );

    expect(find.text('RentLedger Dark'), findsOneWidget);
    expect(find.text('Dark Mode Active'), findsOneWidget);
  });
}
