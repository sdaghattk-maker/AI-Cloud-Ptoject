import 'package:flutter/material.dart';
import '../engine/chart_data.dart';
import '../engine/decision.dart';
import '../engine/engine.dart';
import '../paper/paper_trade.dart';
import '../services/errors.dart';
import '../services/settings.dart';
import '../widgets/candle_chart.dart';
import '../widgets/result_view.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key, this.symbol, this.timeframe, this.trade});
  final String? symbol, timeframe;
  final PaperTrade? trade; // اگر باشد، سطوح همان معامله آزمایشی هم رسم می‌شود

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late String _symbol;
  late String _tf;
  ChartOptions _opts = const ChartOptions();
  ChartData? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _symbol = widget.symbol ?? Settings.symbols.first;
    _tf = widget.timeframe ?? '1h';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await Engine.chart(_symbol, _tf);
      if (!mounted) return;
      setState(() => _data = d);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'خطا در ساخت چارت: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<LevelOverlay> _overlays(ChartData d) {
    final list = <LevelOverlay>[];
    final live = d.liveOverlay;
    if (live != null) list.add(live);
    final t = widget.trade;
    if (t != null && t.symbol == d.symbol && t.timeframe == d.timeframe) {
      final idx = indexOfTime(d.times, t.signalTimeMs);
      list.add(LevelOverlay(
        label: 'معامله آزمایشی',
        side: t.side,
        startIndex: idx < 0 ? 0 : idx,
        entry: t.entry,
        sl: t.sl,
        tp1: t.tp1,
        tp2: t.tp2,
        dashed: true,
      ));
    }
    return list;
  }

  double _chartHeight() {
    var h = 330.0;
    if (_opts.volume) h += 60;
    if (_opts.rsi) h += 100;
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final symbols = {...Settings.symbols, _symbol}.toList();
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('چارت'),
        actions: [
          IconButton(
            tooltip: 'به‌روزرسانی',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _symbol,
              items: [
                for (final s in symbols)
                  DropdownMenuItem(value: s, child: Text(s, textDirection: TextDirection.ltr))
              ],
              onChanged: _loading
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _symbol = v);
                      _load();
                    },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '15m', label: Text('15m')),
            ButtonSegment(value: '1h', label: Text('1h')),
            ButtonSegment(value: '4h', label: Text('4h')),
            ButtonSegment(value: '1d', label: Text('1d')),
          ],
          selected: {_tf},
          onSelectionChanged: _loading
              ? null
              : (v) {
                  setState(() => _tf = v.first);
                  _load();
                },
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('در حال دریافت داده و تحلیل روی گوشی…'),
            ]),
          )
        else if (_error != null)
          Column(children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('تلاش دوباره')),
          ])
        else if (d != null) ...[
          _verdictStrip(d),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              height: _chartHeight(),
              child: CandleChart(
                key: ValueKey('${d.symbol}|${d.timeframe}'),
                data: d,
                overlays: _overlays(d),
                options: _opts,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _toggles(),
          const SizedBox(height: 4),
          Text(
            'کشیدن: جابه‌جایی · دو انگشت: زوم · لمس یک کندل: جزئیات. '
            '${d.markers.isEmpty ? '' : 'مثلث‌ها معاملات تاریخی استراتژی «${d.strategyName}» هستند (سبز سود، قرمز ضرر؛ عدد = R). '}'
            'خط‌چین‌های R/S سطوح مقاومت/حمایت‌اند.',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 12),
          ResultView(result: d.result),
        ],
      ]),
    );
  }

  Widget _verdictStrip(ChartData d) {
    final dec = d.decision;
    final color = switch (dec.verdict) {
      Verdict.enter => const Color(0xFF2E9E5B),
      Verdict.wait => const Color(0xFFE0A100),
      Verdict.avoid => const Color(0xFFD64545),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Text(dec.title,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            dec.verdict == Verdict.enter ? dec.subtitle : '',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (dec.strength.isNotEmpty)
          Text('شواهد: ${dec.strength}', style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _toggles() {
    Widget chip(String label, bool value, ChartOptions Function(bool) apply) =>
        FilterChip(
          label: Text(label),
          selected: value,
          onSelected: (v) => setState(() => _opts = apply(v)),
        );
    return Wrap(spacing: 6, runSpacing: 0, children: [
      chip('EMA50', _opts.ema50, (v) => _opts.copyWith(ema50: v)),
      chip('EMA200', _opts.ema200, (v) => _opts.copyWith(ema200: v)),
      chip('بولینگر', _opts.bb, (v) => _opts.copyWith(bb: v)),
      chip('حجم', _opts.volume, (v) => _opts.copyWith(volume: v)),
      chip('RSI', _opts.rsi, (v) => _opts.copyWith(rsi: v)),
      chip('معاملات تاریخی', _opts.markers, (v) => _opts.copyWith(markers: v)),
      chip('حمایت/مقاومت', _opts.levels, (v) => _opts.copyWith(levels: v)),
    ]);
  }
}
