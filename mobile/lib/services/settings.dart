import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const defaultSymbols = [
    'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT',
    'ADAUSDT', 'DOGEUSDT', 'AVAXUSDT', 'LINKUSDT', 'TONUSDT',
  ];

  static List<String> symbols = List.of(defaultSymbols);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList('symbols');
    if (saved != null && saved.isNotEmpty) symbols = saved;
  }

  static Future<void> saveSymbols(List<String> list) async {
    symbols = list;
    final p = await SharedPreferences.getInstance();
    await p.setStringList('symbols', list);
  }
}
