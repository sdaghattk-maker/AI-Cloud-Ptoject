import 'package:flutter/material.dart';
import '../engine/engine.dart';
import '../ml/ml_filter.dart';
import '../widgets/ai_profile_editor.dart';
import 'research_screen.dart';
import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _symbols = TextEditingController(text: Settings.symbols.join(', '));
  late Future<Map<String, MlModel>> _ml;

  @override
  void initState() {
    super.initState();
    _ml = MlStore.loadAll(defaultTimeframes);
  }

  @override
  void dispose() {
    _symbols.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ---------------- گزارش پژوهشی ----------------
        Card(
          child: ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('گزارش پژوهشی'),
            subtitle: const Text(
                'تحلیل همه نمادها در یک متن فشرده برای کپی و بررسی آماری'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ResearchScreen())),
          ),
        ),
        const SizedBox(height: 16),

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
        const Text('هوش مصنوعی (توضیح تحلیل)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'تا دو سرویس AI می‌توانید تنظیم کنید (مثلاً Gemini و Groq). '
          'کلید رایگان: Gemini از aistudio.google.com ← Get API key ، Groq از console.groq.com. '
          'AI فقط داده‌های محاسبه‌شده را توضیح می‌دهد. کلیدها فقط روی همین گوشی ذخیره می‌شوند. '
          'در بعضی کشورها این سرویس‌ها بدون VPN باز نمی‌شوند.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        const Text('حالت استفاده:'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          ChoiceChip(
            label: const Text('خودکار (اگر اولی خطا داد، دومی)'),
            selected: Settings.aiMode == 'auto',
            onSelected: (_) async {
              await Settings.saveAiMode('auto');
              if (mounted) setState(() {});
            },
          ),
          ChoiceChip(
            label: const Text('هر دو (مقایسه پاسخ‌ها)'),
            selected: Settings.aiMode == 'both',
            onSelected: (_) async {
              await Settings.saveAiMode('both');
              if (mounted) setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 8),
        const AiProfileEditor(index: 0),
        const AiProfileEditor(index: 1),
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
