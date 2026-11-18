import 'package:flutter/material.dart';
import '../engine/engine.dart';
import '../ml/ml_filter.dart';
import '../services/llm.dart';
import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _symbols = TextEditingController(text: Settings.symbols.join(', '));
  final _base = TextEditingController(text: Settings.llmBaseUrl);
  final _model = TextEditingController(text: Settings.llmModel);
  final _key = TextEditingController(text: Settings.llmKey);
  bool _showKey = false;
  late Future<Map<String, MlModel>> _ml;

  @override
  void initState() {
    super.initState();
    _ml = MlStore.loadAll(defaultTimeframes);
  }

  @override
  void dispose() {
    _symbols.dispose();
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  List<String> _parseSymbols() => _symbols.text
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim().toUpperCase())
      .where((e) => e.isNotEmpty)
      .toList();

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _preset(String base, String model) {
    setState(() {
      _base.text = base;
      _model.text = model;
    });
  }

  Future<void> _saveLlm() async {
    await Settings.saveLlm(_base.text, _model.text, _key.text);
    _snack('تنظیمات AI ذخیره شد');
  }

  Future<void> _pickModel() async {
    await Settings.saveLlm(_base.text, _model.text, _key.text);
    try {
      final models = await Llm.listModels();
      if (!mounted) return;
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => ListView(children: [
          for (final m in models)
            ListTile(
              title: Text(m, textDirection: TextDirection.ltr),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ]),
      );
      if (picked != null) setState(() => _model.text = picked);
    } catch (e) {
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ---------------- نمادها ----------------
        const Text('نمادهای اسکن (جفت‌ارز با USDT، جداشده با ویرگول)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _symbols,
          minLines: 2,
          maxLines: 5,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 4),
        const Text('تعداد نمادهای کمتر = اسکن سریع‌تر. برای آموزش بهتر ML حداقل ۸ نماد بگذارید.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () async {
                final list = _parseSymbols();
                if (list.isEmpty) return;
                await Settings.saveSymbols(list);
                _snack('ذخیره شد؛ اسکن بعدی از لیست جدید استفاده می‌کند');
              },
              child: const Text('ذخیره نمادها'),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => setState(
                () => _symbols.text = Settings.defaultSymbols.join(', ')),
            child: const Text('پیش‌فرض'),
          ),
        ]),
        const Divider(height: 36),

        // ---------------- هوش مصنوعی ----------------
        const Text('هوش مصنوعی (توضیح سیگنال)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'کلید رایگان: Gemini از aistudio.google.com ← Get API key ، یا Groq از console.groq.com. '
          'AI فقط داده‌های محاسبه‌شده را توضیح می‌دهد. کلید فقط روی همین گوشی ذخیره می‌شود. '
          'در بعضی کشورها این سرویس‌ها بدون VPN باز نمی‌شوند.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          ActionChip(
            label: const Text('Gemini'),
            onPressed: () => _preset(
                'https://generativelanguage.googleapis.com/v1beta/openai/',
                'gemini-flash-latest'),
          ),
          ActionChip(
            label: const Text('Groq'),
            onPressed: () =>
                _preset('https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile'),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _base,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              labelText: 'آدرس پایه API', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _model,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
              labelText: 'نام مدل', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _key,
          obscureText: !_showKey,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: 'کلید API',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton(
                onPressed: _saveLlm, child: const Text('ذخیره تنظیمات AI')),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
              onPressed: _pickModel, child: const Text('دریافت لیست مدل‌ها')),
        ]),
        const Divider(height: 36),

        // ---------------- وضعیت ML ----------------
        const Text('وضعیت فیلتر یادگیری ماشین',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'مدل هر تایم‌فریم هنگام «اسکن بازار» روی معاملات تاریخی همه نمادها آموزش می‌بیند و '
          'فقط اگر روی داده‌های دیده‌نشده برتری معنادار نشان دهد، سیگنال‌ها را فیلتر می‌کند.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, MlModel>>(
          future: _ml,
          builder: (context, snap) {
            if (!snap.hasData) return const LinearProgressIndicator();
            final models = snap.data!;
            if (models.isEmpty) {
              return const Text('هنوز آموزش ندیده؛ یک‌بار اسکن بازار را اجرا کنید.');
            }
            return Column(children: [
              for (final tf in defaultTimeframes)
                if (models[tf] != null) _mlTile(tf, models[tf]!),
            ]);
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'تمام تحلیل‌ها روی همین گوشی انجام می‌شود و داده از API عمومی بایننس گرفته می‌شود.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
    );
  }

  Widget _mlTile(String tf, MlModel m) {
    final r = m.report;
    return Card(
      child: ListTile(
        dense: true,
        title: Text('$tf — ${m.approved ? 'تأییدشده (فیلتر فعال)' : 'تأییدنشده (فقط اطلاعاتی)'}'),
        subtitle: Text(
          'نمونه‌ها ${r.samples} · آزمون خارج از نمونه ${r.oosTrades} معامله\n'
          'میانگین پایه ${r.baseExpectancy.toStringAsFixed(2)}R ← '
          'فیلترشده ${r.filteredExpectancy.toStringAsFixed(2)}R '
          '(${r.filteredTrades} معامله) · t=${r.tStat.toStringAsFixed(1)}',
        ),
        isThreeLine: true,
      ),
    );
  }
}
