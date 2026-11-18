import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const defaultSymbols = [
    'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT',
    'ADAUSDT', 'DOGEUSDT', 'AVAXUSDT', 'LINKUSDT', 'TONUSDT',
  ];

  static List<String> symbols = List.of(defaultSymbols);

  // تنظیمات سرویس AI (هر سرویس سازگار با OpenAI؛ کلید فقط روی همین گوشی ذخیره می‌شود)
  static String llmBaseUrl = '';
  static String llmModel = '';
  static String llmKey = '';
  static bool get llmReady =>
      llmBaseUrl.isNotEmpty && llmModel.isNotEmpty && llmKey.isNotEmpty;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList('symbols');
    if (saved != null && saved.isNotEmpty) symbols = saved;
    llmBaseUrl = p.getString('llmBaseUrl') ?? '';
    llmModel = p.getString('llmModel') ?? '';
    llmKey = p.getString('llmKey') ?? '';
  }

  static Future<void> saveSymbols(List<String> list) async {
    symbols = list;
    final p = await SharedPreferences.getInstance();
    await p.setStringList('symbols', list);
  }

  static Future<void> saveLlm(String baseUrl, String model, String key) async {
    llmBaseUrl = baseUrl.trim();
    llmModel = model.trim();
    llmKey = key.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('llmBaseUrl', llmBaseUrl);
    await p.setString('llmModel', llmModel);
    await p.setString('llmKey', llmKey);
  }
}
