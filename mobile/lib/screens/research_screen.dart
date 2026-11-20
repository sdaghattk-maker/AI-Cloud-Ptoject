import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/engine.dart';
import '../research/report.dart';
import '../services/errors.dart';
import '../services/settings.dart';

/// گزارش پژوهشی: Walk-Forward همه نمادها و تایم‌فریم‌ها در یک متن فشرده برای کپی و ارسال
class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key});

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  bool _running = false;
  int _done = 0, _total = 0;
  String? _report, _error;
  ResearchData? _data;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _report = null;
      _done = 0;
      _total = 0;
    });
    try {
      final data = await Engine.research(onProgress: (d, t) {
        if (!mounted) return;
        setState(() {
          _done = d;
          _total = t;
        });
      });
      if (!mounted) return;
      setState(() {
        _data = data;
        _report = buildResearchReport(data.rows, failures: data.failures);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _copy() async {
    final r = _report;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: r));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('گزارش کپی شد؛ آن را در چت بچسبانید')));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final passed = data?.rows.where((r) => r.result.edgeOk).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش پژوهشی')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Text(
          'این گزارش Walk-Forward همه نمادهای تنظیمات (${Settings.symbols.length} نماد) روی ۴ تایم‌فریم را '
          'اجرا می‌کند و نتیجه را در یک متن فشرده می‌دهد: آمار هر سری، تعداد سری‌های موفق در برابر '
          'شانس، عملکرد هر خانواده استراتژی بدون انتخاب پارامتر، و تفکیک خرید/فروش. '
          'با کپی‌کردن و فرستادن همین متن، می‌شود بدون اسکرین‌شات تک‌تک سری‌ها بررسی کرد '
          'که واقعاً لبه‌ای وجود دارد یا نه. چیزی ثبت یا معامله‌ای باز نمی‌شود.',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 6),
        const Text('اپ باید باز بماند؛ ممکن است ۲ تا ۵ دقیقه طول بکشد.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.science_outlined),
          label: Text(_report == null ? 'شروع تحلیل' : 'تحلیل دوباره'),
        ),
        const SizedBox(height: 12),
        if (_running) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          const SizedBox(height: 6),
          Text('$_done از $_total'),
        ],
        if (_error != null) Text(_error!),
        if (_report != null && data != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${data.rows.length} سری تحلیل شد'
                    '${data.failures.isEmpty ? '' : ' (${data.failures.length} خطا)'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('گذرنده از گیت: $passed از ${data.rows.length} '
                    '(بدون هیچ لبه واقعی هم تا ~${(data.rows.length * 0.067).toStringAsFixed(1)} مورد شانسی ممکن است)'),
              ]),
            ),
          ),
          FilledButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy),
            label: Text('کپی گزارش (${_report!.length} کاراکتر)'),
          ),
          const SizedBox(height: 10),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _report!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
