import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  /// 10.0.2.2 = localhost کامپیوتر از داخل شبیه‌ساز اندروید
  static String baseUrl = 'http://10.0.2.2:8000';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? baseUrl;
  }

  static Future<void> save(String url) async {
    baseUrl = url.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
  }
}
