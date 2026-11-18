import 'package:flutter/material.dart';
import '../services/llm.dart';
import '../services/settings.dart';

const _geminiUrl = 'https://generativelanguage.googleapis.com/v1beta/openai/';
const _groqUrl = 'https://api.groq.com/openai/v1';

/// ویرایشگر یکی از دو جایگاه AI
class AiProfileEditor extends StatefulWidget {
  const AiProfileEditor({super.key, required this.index});
  final int index; // 0 یا 1

  @override
  State<AiProfileEditor> createState() => _AiProfileEditorState();
}

class _AiProfileEditorState extends State<AiProfileEditor> {
  late final TextEditingController _base;
  late final TextEditingController _model;
  late final TextEditingController _key;
  bool _showKey = false;

  AiProfile get _saved => Settings.aiProfiles[widget.index];

  @override
  void initState() {
    super.initState();
    _base = TextEditingController(text: _saved.baseUrl);
    _model = TextEditingController(text: _saved.model);
    _key = TextEditingController(text: _saved.key);
  }

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  AiProfile get _current =>
      AiProfile(baseUrl: _base.text, model: _model.text, key: _key.text);

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

  Future<void> _save() async {
    await Settings.saveAiProfile(widget.index, _current);
    if (!mounted) return;
    setState(() {});
    _snack('AI ${widget.index + 1} ذخیره شد');
  }

  Future<void> _pickModel() async {
    try {
      final models = await Llm.listModels(_current);
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
    final i = widget.index;
    final ready = _saved.ready;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: !ready,
        title: Text('AI ${i + 1}'),
        subtitle: Text(
          ready ? '${_saved.label(i)} · ${_saved.model}' : 'تنظیم نشده',
          textDirection: TextDirection.ltr,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          Wrap(spacing: 8, children: [
            ActionChip(
                label: const Text('Gemini'),
                onPressed: () => _preset(_geminiUrl, 'gemini-flash-latest')),
            ActionChip(
                label: const Text('Groq'),
                onPressed: () => _preset(_groqUrl, 'llama-3.3-70b-versatile')),
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
                child: FilledButton(onPressed: _save, child: const Text('ذخیره'))),
            const SizedBox(width: 10),
            OutlinedButton(
                onPressed: _pickModel, child: const Text('دریافت لیست مدل‌ها')),
          ]),
        ],
      ),
    );
  }
}
