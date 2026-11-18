import 'package:flutter/material.dart';
import '../models/signal.dart';
import '../services/errors.dart';
import '../services/llm.dart';
import '../services/settings.dart';

/// کارت ML: احتمال موفقیت و وضعیت تأیید فیلتر
class MlCard extends StatelessWidget {
  const MlCard({super.key, required this.signal});
  final Signal signal;

  @override
  Widget build(BuildContext context) {
    final s = signal;
    if (s.mlStatus.isEmpty) return const SizedBox.shrink();
    final p = s.mlProb;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('فیلتر یادگیری ماشین',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (p != null) ...[
            LinearProgressIndicator(value: p.clamp(0.0, 1.0)),
            const SizedBox(height: 6),
            Text('احتمال موفقیت (تخمین مدل): ${(p * 100).round()}٪'),
            const SizedBox(height: 6),
          ],
          Text(s.mlStatus, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

/// کارت تحلیل هوشمند: هم برای سیگنال و هم برای حالت «بدون سیگنال» استفاده می‌شود.
/// بسته به تنظیمات، پاسخ یک AI یا مقایسه پاسخ دو AI را نشان می‌دهد.
class AiAnalysisCard extends StatefulWidget {
  const AiAnalysisCard({
    super.key,
    required this.cacheKey,
    required this.system,
    required this.prompt,
    this.title = 'تحلیل هوشمند (AI)',
  });
  final String cacheKey, system, prompt, title;

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
              'برای فعال‌سازی: تب «تنظیمات» ← «هوش مصنوعی»، آدرس و مدل و کلید را وارد و ذخیره کنید. '
              'سپس به همین صفحه برگردید.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            FilledButton.icon(
              onPressed: _loading ? null : _run,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_answers == null ? 'تحلیل هوشمند' : 'تحلیل دوباره'),
            ),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_answers != null)
              for (final a in _answers!) _answerView(a),
            if (_answers != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
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
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${a.label} · ${a.model}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        a.ok ? SelectableText(a.text) : Text('خطا: ${a.text}'),
        const Divider(),
      ]),
    );
  }
}
