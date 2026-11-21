import 'package:flutter/material.dart';
import '../models/signal.dart';
import '../paper/paper_store.dart';
import '../paper/paper_trade.dart';
import '../services/errors.dart';
import '../widgets/stats_card.dart';
import 'chart_screen.dart';

class PaperScreen extends StatefulWidget {
  const PaperScreen({super.key});

  @override
  State<PaperScreen> createState() => _PaperScreenState();
}

class _PaperScreenState extends State<PaperScreen> {
  List<PaperTrade> _trades = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await PaperEngine.refresh();
      if (!mounted) return;
      setState(() => _trades = list);
    } on ApiException catch (e) {
      final cached = await PaperStore.load(); // حداقل آخرین وضعیت ذخیره‌شده را نشان بده
      if (!mounted) return;
      setState(() {
        _trades = cached;
        _error = e.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک کردن همه معاملات آزمایشی؟'),
        content: const Text('این کار قابل بازگشت نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('پاک شود')),
        ],
      ),
    );
    if (ok == true) {
      await PaperStore.clear();
      if (mounted) setState(() => _trades = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = summarize(_trades);
    return Scaffold(
      appBar: AppBar(
        title: const Text('معاملات آزمایشی'),
        actions: [
          IconButton(
              tooltip: 'به‌روزرسانی', onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: 'پاک کردن', onPressed: _trades.isEmpty ? null : _confirmClear, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(_error!),
              ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'هر سیگنالی که اپ می‌دهد در لحظه صدور و پیش از دانستن نتیجه ثبت می‌شود و بعداً با قیمت '
                  'واقعی بازار ارزیابی می‌شود (بدون پول واقعی). این معتبرترین آزمون روی آینده است. '
                  'اپ فقط وقتی باز است اسکن می‌کند؛ سیگنال‌های زمان بسته‌بودن اپ ثبت نمی‌شوند.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            _summaryCard(s),
            if (_trades.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'هنوز معامله‌ای ثبت نشده. وقتی اسکن یا تحلیل سیگنالی بدهد، اینجا ثبت می‌شود.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final t in _trades) _tile(t),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(PaperSummary s) {
    if (s.total == 0) return const SizedBox.shrink();
    final groups = s.byStrength.entries
        .map((e) => '${e.key}: ${e.value.n} معامله، میانگین ${e.value.avgR.toStringAsFixed(2)}R')
        .join('\n');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (s.closed > 0)
        StatsCard(stats: s.stats, title: 'نتیجه زنده (${s.closed} معامله بسته‌شده، ${s.open} باز)'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(liveVerdict(s), style: const TextStyle(fontWeight: FontWeight.w600)),
            if (s.closed > 0) ...[
              const SizedBox(height: 8),
              Text(
                'میانگین انتظار بک‌تست هنگام صدور: ${s.avgBacktestR.toStringAsFixed(2)}R  ←  '
                'نتیجه زنده: ${s.stats.expectancyR.toStringAsFixed(2)}R',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('به تفکیک قدرت شواهد:', style: TextStyle(fontSize: 12)),
              Text(groups, style: const TextStyle(fontSize: 12)),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _tile(PaperTrade t) {
    const green = Color(0xFF2E9E5B);
    const red = Color(0xFFD64545);
    final closed = t.isClosed;
    final win = closed && t.resultR! > 0;
    final color = !closed ? Colors.amber : (win ? green : red);
    final icon = !closed ? Icons.hourglass_top : (win ? Icons.check_circle : Icons.cancel);
    final status = closed
        ? outcomeLabel(t.outcome)
        : (t.tp1Hit ? 'باز · هدف اول خورده، SL روی ورود' : 'باز');
    return Card(
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChartScreen(symbol: t.symbol, timeframe: t.timeframe, trade: t))),
        leading: Icon(icon, color: color),
        title: Text('${t.symbol} · ${t.timeframe} · ${t.isLong ? 'خرید' : 'فروش'}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          'ورود ${fmt(t.entry)} · SL ${fmt(t.sl)} · TP2 ${fmt(t.tp2)}\n'
          '$status · شواهد: ${t.strength}',
        ),
        isThreeLine: true,
        trailing: closed
            ? Text('${t.resultR! >= 0 ? '+' : ''}${t.resultR!.toStringAsFixed(2)}R',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15))
            : null,
      ),
    );
  }
}
