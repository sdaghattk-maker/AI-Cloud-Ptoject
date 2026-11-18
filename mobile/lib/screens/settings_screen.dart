import 'package:flutter/material.dart';
import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _symbols = TextEditingController(text: Settings.symbols.join(', '));

  @override
  void dispose() {
    _symbols.dispose();
    super.dispose();
  }

  List<String> _parse() => _symbols.text
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim().toUpperCase())
      .where((e) => e.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('نمادهای اسکن (جفت‌ارز با USDT، جداشده با ویرگول)'),
        const SizedBox(height: 8),
        TextField(
          controller: _symbols,
          minLines: 2,
          maxLines: 5,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        const Text(
          'هر نماد روی ۴ تایم‌فریم تحلیل می‌شود. تعداد نمادها کمتر = اسکن سریع‌تر.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () async {
                final list = _parse();
                if (list.isEmpty) return;
                await Settings.saveSymbols(list);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('ذخیره شد؛ اسکن بعدی از لیست جدید استفاده می‌کند')));
              },
              child: const Text('ذخیره'),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () {
              setState(() => _symbols.text = Settings.defaultSymbols.join(', '));
            },
            child: const Text('پیش‌فرض'),
          ),
        ]),
        const SizedBox(height: 24),
        const Text(
          'تمام تحلیل‌ها روی همین گوشی انجام می‌شود و داده از API عمومی بایننس '
          'گرفته می‌شود؛ نیازی به سرور یا حساب ندارد.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
    );
  }
}
