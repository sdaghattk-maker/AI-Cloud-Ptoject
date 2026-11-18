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

/// کارت تحلیل هوشمند: LLM همان داده‌های محاسبه‌شده را به زبان ساده توضیح می‌دهد
class AiAnalysisCard extends StatefulWidget {
  const AiAnalysisCard({super.key, required this.signal});
  final Signal signal;

  @override
  State<AiAnalysisCard> createState() => _AiAnalysisCardState();
}

class _AiAnalysisCardState extends State<AiAnalysisCard> {
  bool _loading = false;
  String? _text, _error;

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await Llm.analyze(widget.signal);
      if (!mounted) return;
      setState(() => _text = t);
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
          const Text('تحلیل هوشمند (AI)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (!Settings.llmReady)
            const Text(
              'برای فعال‌سازی: تب «تنظیمات» ← بخش «هوش مصنوعی»، یک کلید رایگان وارد کنید.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            FilledButton.icon(
              onPressed: _loading ? null : _run,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_text == null ? 'تحلیل هوشمند' : 'تحلیل دوباره'),
            ),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_text != null) SelectableText(_text!),
            if (_text != null)
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
}
