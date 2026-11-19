import 'package:flutter/material.dart';
import '../services/ai_brief.dart';
import '../services/errors.dart';
import '../services/llm.dart';
import '../services/settings.dart';

/// نظر کوتاه AI: «چرا؟»، «ریسک‌ها» و یک جمله پایانی. تصمیم اصلی را کارت تصمیم می‌دهد.
/// بسته به تنظیمات، پاسخ یک AI یا مقایسه پاسخ دو AI را نشان می‌دهد.
class AiAnalysisCard extends StatefulWidget {
  const AiAnalysisCard({
    super.key,
    required this.cacheKey,
    required this.system,
    required this.prompt,
    this.title = 'نظر AI (خلاصه)',
    this.lastLabel = 'شرط ابطال',
  });
  final String cacheKey, system, prompt, title, lastLabel;

  @override
  State<AiAnalysisCard> createState() => _AiAnalysisCardState();
}

class _AiAnalysisCardState extends State<AiAnalysisCard> {
  bool _loading = false;
  List<AiAnswer>? _answers;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final a = await Llm.ask(widget.cacheKey, widget.system, widget.prompt);
      if (!mounted) return;
      setState(() => _answers = a);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (!Settings.llmReady)
            const Text(
              'اختیاری: برای نظر AI، در تب «تنظیمات» ← «هوش مصنوعی» یک کلید وارد کنید. '
              'تصمیم اپ بالای این صفحه بدون AI هم کار می‌کند.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            FilledButton.icon(
              onPressed: _loading ? null : _run,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_answers == null ? 'نظر AI' : 'دوباره'),
            ),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_answers != null)
              for (final a in _answers!) _answerView(a),
            if (_answers != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'AI فقط داده‌های محاسبه‌شده را توضیح می‌دهد و ممکن است اشتباه کند.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _answerView(AiAnswer a) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${a.label} · ${a.model}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (!a.ok)
          Text('خطا: ${a.text}')
        else
          _brief(a.text),
        const Divider(),
      ]),
    );
  }

  Widget _brief(String text) {
    final b = parseAiBrief(text);
    if (b == null) {
      // اگر مدل JSON نداد، متن را کوتاه نشان بده
      return SelectableText(text.length > 500 ? '${text.substring(0, 500)}…' : text,
          style: const TextStyle(fontSize: 13));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (b.reasons.isNotEmpty) _section('چرا؟', b.reasons, Icons.check_circle_outline),
      if (b.risks.isNotEmpty) _section('ریسک‌ها', b.risks, Icons.warning_amber_rounded),
      if (b.invalidation.isNotEmpty)
        _section(widget.lastLabel, [b.invalidation], Icons.flag_outlined),
    ]);
  }

  Widget _section(String title, List<String> items, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Expanded(child: SelectableText(it, style: const TextStyle(fontSize: 13))),
            ]),
          ),
      ]),
    );
  }
}
