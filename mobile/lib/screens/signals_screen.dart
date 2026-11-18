import 'package:flutter/material.dart';
import '../models/signal.dart';
import '../services/api.dart';
import 'signal_detail_screen.dart';

class SignalsScreen extends StatefulWidget {
  const SignalsScreen({super.key});

  @override
  State<SignalsScreen> createState() => _SignalsScreenState();
}

class _SignalsScreenState extends State<SignalsScreen> {
  List<Signal> _all = [];
  bool _loading = true;
  String? _error;
  String _filter = 'ALL';
  int _done = 0, _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _done = 0;
      _total = 0;
    });
    try {
      final data = await Api().scan(onProgress: (d, t) {
        if (!mounted) return;
        setState(() {
          _done = d;
          _total = t;
        });
      });
      if (!mounted) return;
      setState(() => _all = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filter == 'ALL'
        ? _all
        : _all.where((s) => s.side == _filter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('سیگنال‌های بازار')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, children: [
            for (final f in const [
              ['ALL', 'همه'],
              ['LONG', 'خرید'],
              ['SHORT', 'فروش']
            ])
              ChoiceChip(
                label: Text(f[1]),
                selected: _filter == f[0],
                onSelected: (_) => setState(() => _filter = f[0]),
              ),
          ]),
        ),
        Expanded(child: _content(list)),
      ]),
    );
  }

  Widget _content(List<Signal> list) {
    if (_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            const SizedBox(height: 16),
            Text(
              'در حال دریافت داده و بک‌تست روی گوشی… ($_done از $_total)\n'
              'برنامه را باز نگه دارید؛ ممکن است ۱ تا ۳ دقیقه طول بکشد.',
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('تلاش دوباره')),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: list.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
              SizedBox(height: 120),
              Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'فعلاً سیگنالی که از فیلتر بک‌تست عبور کند وجود ندارد.\n'
                  'نبودن سیگنال هم یک نتیجه معتبر است؛ وارد معامله بی‌دلیل نشوید.',
                  textAlign: TextAlign.center,
                ),
              ),
            ])
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length,
              itemBuilder: (_, i) => _SignalTile(signal: list[i]),
            ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.signal});
  final Signal signal;

  @override
  Widget build(BuildContext context) {
    final s = signal;
    final color = s.isLong ? const Color(0xFF2E9E5B) : const Color(0xFFD64545);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SignalDetailScreen(signal: s))),
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(s.isLong ? Icons.trending_up : Icons.trending_down,
              color: Colors.white),
        ),
        title: Text('${s.symbol} · ${s.timeframe}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            'ورود ${fmt(s.entry)}  |  SL ${fmt(s.sl)}\n'
            'وین‌ریت ${s.backtest.winRate}٪  ·  میانگین ${s.backtest.expectancyR}R'),
        isThreeLine: true,
        trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(s.score.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Text('امتیاز', style: TextStyle(fontSize: 10)),
            ]),
      ),
    );
  }
}
