import 'package:flutter/material.dart';

import 'config/theme.dart';
import 'ui/dashboard/dashboard_page.dart';
import 'ui/history/history_page.dart';
import 'ui/settings/settings_page.dart';

/// Root aplikasi: tema gelap + navigasi bawah (Dashboard / Riwayat / Pengaturan).
class ScalpSignalsApp extends StatelessWidget {
  const ScalpSignalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scalp Signals',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();
  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  final _pages = const [
    DashboardPage(),
    HistoryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'Riwayat'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined), label: 'Pengaturan'),
        ],
      ),
    );
  }
}
