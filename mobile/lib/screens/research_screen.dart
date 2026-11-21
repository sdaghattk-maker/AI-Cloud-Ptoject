import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/decision.dart';
import '../engine/engine.dart';
import '../research/daily.dart';
import '../research/report.dart';
import '../services/errors.dart';
import '../services/settings.dart';

/// گزارش‌های پژوهشی: متن فشرده برای کپی و بررسی آماری (چیزی ثبت یا معامله‌ای باز نمی‌شود)
class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key});

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  bool _running = false;
  int _done = 0, _total = 0;
  String? _report, _error, _kind;
  ResearchData? _data;
  List<CheckItem>? _checks;

  void _start(String kind) {
    setState(() {
      _running = true;
      _error = null;
      _report = null;
      _checks = null;
      _data = null;
      _kind = kind;
      _done = 0;
      _total = 0;
    });
  }

  void _progress(int d, int t) {
    if (!mounted) return;
    setState(() {
      _done = d;
      _total = t;
    });
  }

  Future<void> _runFull() async {
    _start('full');
    try {
      final data = await Engine.research(onProgress: _progress);
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

  Future<void> _runDaily() async {
    _start('daily');
    try {
      final data = await Engine.dailyValidation(onProgress: _progress);
      if (!mounted) return;
      setState(() {
        _checks = dailyChecks(data.rows);
        _report = buildDailyReport(data.rows, failures: data.failures);
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
    final passedGate = data?.rows.where((r) => r.result.edgeOk).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش پژوهشی')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Text(
          'دو گزارش وجود دارد. «اعتبارسنجی روزانه» بررسی می‌کند که تنها نامزد باقی‌مانده (شکست کانال '
          'روی روزانه) در برابر تقسیم زمانی، حذف نمادها، تغییر پارامتر و پرتفوی واقعی دوام می‌آورد یا نه. '
          '«گزارش کامل» همه تایم‌فریم‌ها را مقایسه می‌کند. اپ باید باز بماند '
          '(روزانه: ۱ تا ۲ دقیقه، کامل: ۲ تا ۵ دقیقه). نمادها از تنظیمات می‌آیند '
          '(الان ${Settings.symbols.length} نماد).',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _running ? null : _runDaily,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('اعتبارسنجی روزانه (شکست کانال)'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _running ? null : _runFull,
          icon: const Icon(Icons.science_outlined),
          label: const Text('گزارش کامل (۴ تایم‌فریم)'),
        ),
        const SizedBox(height: 12),
        if (_running) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          const SizedBox(height: 6),
          Text('$_done از $_total'),
        ],
        if (_error != null) Text(_error!),
        if (_checks != null) _checksCard(_checks!),
        if (_kind == 'full' && data != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${data.rows.length} سری تحلیل شد'
                    '${data.failures.isEmpty ? '' : ' (${data.failures.length} خطا)'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('گذرنده از گیت: $passedGate از ${data.rows.length} '
                    '(بدون هیچ لبه واقعی هم تا ~${(data.rows.length * 0.067).toStringAsFixed(1)} مورد شانسی ممکن است)'),
              ]),
            ),
          ),
        if (_report != null) ...[
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

  Widget _checksCard(List<CheckItem> checks) {
    final passed = checks.where((c) => c.ok == true).length;
    final all = passed == checks.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$passed از ${checks.length} شرط برقرار است',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            all
                ? 'همه برقرار است؛ این هنوز اثبات نیست (سوگیری بقا و همبستگی ارزها)، ولی '
                    'ارزش ادامه با Paper Trading را دارد.'
                : 'حداقل یک شرط برقرار نیست؛ یعنی نتیجه شکننده است و به آن پول واقعی ندهید.',
            style: const TextStyle(fontSize: 12),
          ),
          const Divider(height: 18),
          for (final c in checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(c.ok == true ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: c.ok == true ? const Color(0xFF2E9E5B) : const Color(0xFFD64545)),
                const SizedBox(width: 8),
                Expanded(child: Text(c.label, style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(c.detail,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 11))),
              ]),
            ),
        ]),
      ),
    );
  }
}
