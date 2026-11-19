import 'package:flutter/material.dart';
import '../engine/decision.dart';
import '../models/signal.dart';
import '../services/llm.dart';
import 'ai_card.dart';
import 'decision_card.dart';
import 'signal_body.dart';
import 'stats_card.dart';

/// نمایش نتیجه تحلیل: برای سیگنال، جزئیات کامل؛ برای حالت بدون سیگنال، حکم + آمار + نظر AI
class ResultView extends StatelessWidget {
  const ResultView({super.key, required this.result});
  final AnalyzeResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r.signal != null) return SignalBody(signal: r.signal!);
    return Column(children: [
      DecisionCard(decision: decisionForResult(r)),
      StatsCard(stats: r.backtest),
      AiAnalysisCard(
        title: 'نظر AI (خلاصه)',
        lastLabel: 'چه چیزی را منتظر باشیم؟',
        cacheKey: '${r.symbol}_${r.timeframe}_${r.context['lastPrice']}',
        system: stateSystemPrompt,
        prompt: buildStatePrompt(r),
      ),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text(disclaimer, style: TextStyle(fontSize: 11)),
      ),
    ]);
  }
}
