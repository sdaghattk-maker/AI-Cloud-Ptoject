import 'package:flutter/material.dart';
import 'screens/analyze_screen.dart';
import 'screens/chart_screen.dart';
import 'screens/paper_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signals_screen.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.load();
  runApp(const CryptoSignalApp());
}

class CryptoSignalApp extends StatelessWidget {
  const CryptoSignalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptoSignal AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B82F6),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final Set<int> _built = {0}; // تب‌های سنگین فقط بعد از اولین باز شدن ساخته می‌شوند

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const SignalsScreen();
      case 1:
        return const ChartScreen();
      case 2:
        return const AnalyzeScreen();
      case 3:
        return const PaperScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < 5; i++) _built.contains(i) ? _page(i) : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _built.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt), label: 'سیگنال‌ها'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'چارت'),
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'تحلیل'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'آزمایشی'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'تنظیمات'),
        ],
      ),
    );
  }
}
