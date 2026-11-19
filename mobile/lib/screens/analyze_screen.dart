import 'package:flutter/material.dart';
import '../models/signal.dart';
import '../services/api.dart';
import '../widgets/result_view.dart';
import 'chart_screen.dart';

class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  final _symbol = TextEditingController(text: 'BTCUSDT');
  String _tf = '1h';
  bool _loading = false;
  String? _error;
  AnalyzeResult? _result;

  @override
  void dispose() {
    _symbol.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await Api().analyze(_symbol.text.trim(), _tf);
      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحلیل دستی')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        TextField(
          controller: _symbol,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'نماد (مثلاً BTCUSDT)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '15m', label: Text('15m')),
            ButtonSegment(value: '1h', label: Text('1h')),
            ButtonSegment(value: '4h', label: Text('4h')),
            ButtonSegment(value: '1d', label: Text('1d')),
          ],
          selected: {_tf},
          onSelectionChanged: (v) => setState(() => _tf = v.first),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _loading ? null : _run,
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('تحلیل کن'),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Text(_error!, textAlign: TextAlign.center)
        else if (_result != null)
          ...[
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ChartScreen(symbol: _result!.symbol, timeframe: _result!.timeframe))),
            icon: const Icon(Icons.show_chart),
            label: const Text('نمایش روی چارت'),
          ),
          const SizedBox(height: 8),
          ResultView(result: _result!),
        ],
      ]),
    );
  }
}
