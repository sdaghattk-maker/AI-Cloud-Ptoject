import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/signal.dart';
import '../services/llm.dart';
import 'ai_card.dart';
import 'levels_chart.dart';
import 'risk_calculator.dart';
import 'stats_card.dart';

const disclaimer =
    'این اپ ابزار کمک‌تحلیل است و توصیه مالی نیست. بازار کریپتو پرنوسان است و '
    'سود تضمین‌شده‌ای وجود ندارد. فقط با سرمایه‌ای ریسک کنید که تحمل از دست دادنش را دارید.';

class SignalBody extends StatelessWidget {
  const SignalBody({super.key, required this.signal});
  final Signal signal;

  @override
  Widget build(BuildContext context) {
    final s = signal;
    final color = s.isLong ? const Color(0xFF2E9E5B) : const Color(0xFFD64545);

    Widget row(String label, double v) => ListTile(
          dense: true,
          title: Text(label),
          trailing: Text(fmt(v),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: fmt(v)));
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label کپی شد'), duration: const Duration(seconds: 1)));
          },
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Chip(
          label: Text(s.isLong ? 'خرید (Long)' : 'فروش (Short)',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: color,
        ),
        const SizedBox(width: 8),
        Text('${s.symbol} · ${s.timeframe}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
      if (s.strategy.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('استراتژی: ${s.strategy}', style: const TextStyle(fontSize: 12)),
        ),
      const SizedBox(height: 8),
      LevelsChart(signal: s),
      Card(
        child: Column(children: [
          row('قیمت ورود', s.entry),
          row('حد ضرر (SL)', s.sl),
          row('هدف اول (TP1)', s.tp1),
          row('هدف دوم (TP2)', s.tp2),
          ListTile(
            dense: true,
            title: const Text('ریسک به ریوارد (TP2)'),
            trailing: Text('1 : ${s.rr2.toStringAsFixed(1)}'),
          ),
          ListTile(
            dense: true,
            title: const Text('فاصله SL از ورود'),
            trailing: Text('${s.riskPct.toStringAsFixed(2)}٪'),
          ),
          ListTile(
            dense: true,
            title: const Text('امتیاز سیگنال'),
            trailing: Text('${s.score.toStringAsFixed(0)} / 100'),
          ),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          'استراتژی: با رسیدن به TP1 نیمی از پوزیشن را ببندید و SL را روی قیمت ورود بگذارید.',
          style: TextStyle(fontSize: 12),
        ),
      ),
      StatsCard(stats: s.backtest),
      MlCard(signal: s),
      AiAnalysisCard(
        cacheKey: '${s.symbol}_${s.timeframe}_${s.time}',
        system: signalSystemPrompt,
        prompt: buildPrompt(s),
      ),
      if (s.explanation.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(s.explanation),
          ),
        ),
      RiskCalculator(signal: s),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text(disclaimer, style: TextStyle(fontSize: 11)),
      ),
    ]);
  }
}
