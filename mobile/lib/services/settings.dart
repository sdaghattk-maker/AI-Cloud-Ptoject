import 'package:shared_preferences/shared_preferences.dart';

/// یک سرویس AI سازگار با OpenAI (Gemini / Groq / ...)
class AiProfile {
  final String baseUrl, model, key;
  const AiProfile({this.baseUrl = '', this.model = '', this.key = ''});

  bool get ready => baseUrl.isNotEmpty && model.isNotEmpty && key.isNotEmpty;

  /// نام نمایشی بر اساس آدرس سرویس
  String label(int index) {
    final u = baseUrl.toLowerCase();
    if (u.contains('generativelanguage')) return 'Gemini';
    if (u.contains('groq')) return 'Groq';
    if (u.contains('openrouter')) return 'OpenRouter';
    return 'AI ${index + 1}';
  }
}

class Settings {
  static const defaultSymbols = [
    'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT',
    'ADAUSDT', 'DOGEUSDT', 'AVAXUSDT', 'LINKUSDT', 'TONUSDT',
  ];

  static List<String> symbols = List.of(defaultSymbols);

  /// دو جایگاه AI. حالت 'auto': اولی، و در صورت خطا دومی. حالت 'both': هر دو برای مقایسه.
  static List<AiProfile> aiProfiles = [const AiProfile(), const AiProfile()];
  static String aiMode = 'auto';
  static bool get llmReady => aiProfiles.any((p) => p.ready);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList('symbols');
    if (saved != null && saved.isNotEmpty) symbols = saved;

    final profiles = <AiProfile>[];
    for (var i = 1; i <= 2; i++) {
      profiles.add(AiProfile(
        baseUrl: p.getString('ai${i}_baseUrl') ?? '',
        model: p.getString('ai${i}_model') ?? '',
        key: p.getString('ai${i}_key') ?? '',
      ));
    }
    // مهاجرت از نسخه قبل که فقط یک AI داشت
    final legacyKey = p.getString('llmKey') ?? '';
    if (!profiles[0].ready && legacyKey.isNotEmpty) {
      profiles[0] = AiProfile(
        baseUrl: p.getString('llmBaseUrl') ?? '',
        model: p.getString('llmModel') ?? '',
        key: legacyKey,
      );
    }
    aiProfiles = profiles;
    aiMode = p.getString('aiMode') ?? 'auto';
  }

  static Future<void> saveSymbols(List<String> list) async {
    symbols = list;
    final p = await SharedPreferences.getInstance();
    await p.setStringList('symbols', list);
  }

  static Future<void> saveAiProfile(int index, AiProfile profile) async {
    final fixed = AiProfile(
      baseUrl: profile.baseUrl.trim(),
      model: profile.model.trim(),
      key: profile.key.trim(),
    );
    aiProfiles = [
      for (var i = 0; i < aiProfiles.length; i++) i == index ? fixed : aiProfiles[i]
    ];
    final n = index + 1;
    final p = await SharedPreferences.getInstance();
    await p.setString('ai${n}_baseUrl', fixed.baseUrl);
    await p.setString('ai${n}_model', fixed.model);
    await p.setString('ai${n}_key', fixed.key);
  }

  static Future<void> saveAiMode(String mode) async {
    aiMode = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString('aiMode', mode);
  }
}
