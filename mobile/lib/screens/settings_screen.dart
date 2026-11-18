import 'package:flutter/material.dart';
import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController(text: Settings.baseUrl);

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
              labelText: 'آدرس سرور', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        const Text(
          'شبیه‌ساز اندروید: http://10.0.2.2:8000\n'
          'گوشی واقعی (هم‌شبکه): http://IP-کامپیوتر:8000\n'
          'نسخه نهایی: حتماً آدرس HTTPS',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await Settings.save(_url.text);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('ذخیره شد')));
          },
          child: const Text('ذخیره'),
        ),
      ]),
    );
  }
}
