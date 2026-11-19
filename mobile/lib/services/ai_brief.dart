import 'dart:convert';

/// خلاصه کوتاه ساختاریافته از خروجی AI (دلایل، ریسک‌ها، شرط ابطال)
class AiBrief {
  final List<String> reasons, risks;
  final String invalidation;
  const AiBrief(this.reasons, this.risks, this.invalidation);
  bool get isEmpty => reasons.isEmpty && risks.isEmpty && invalidation.isEmpty;
}

/// پاسخ AI را (حتی اگر داخل بلوک ``` یا همراه متن اضافه باشد) به AiBrief تبدیل می‌کند؛
/// در صورت ناموفق بودن null برمی‌گرداند تا متن خام نشان داده شود.
AiBrief? parseAiBrief(String text) {
  final a = text.indexOf('{');
  final b = text.lastIndexOf('}');
  if (a < 0 || b <= a) return null;
  try {
    final j = jsonDecode(text.substring(a, b + 1));
    if (j is! Map<String, dynamic>) return null;
    List<String> list(dynamic v, int max) => v is List
        ? v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .take(max)
            .toList()
        : <String>[];
    final brief = AiBrief(
      list(j['reasons'], 3),
      list(j['risks'], 2),
      (j['invalidation'] ?? '').toString().trim(),
    );
    return brief.isEmpty ? null : brief;
  } catch (_) {
    return null;
  }
}
