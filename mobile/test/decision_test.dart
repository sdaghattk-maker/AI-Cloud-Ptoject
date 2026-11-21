import 'package:flutter_test/flutter_test.dart';
import 'package:cryptosignal/engine/decision.dart';
import 'package:cryptosignal/models/signal.dart';
import 'package:cryptosignal/services/ai_brief.dart';
import 'package:cryptosignal/services/llm.dart';

BacktestStats stats(
        {double t = 2.5, int trades = 30, double exp = 0.2, double pf = 1.4}) =>
    BacktestStats(
        trades: trades,
        winRate: 50,
        expectancyR: exp,
        profitFactor: pf,
        maxDdR: 3,
        totalR: 6,
        tStat: t);

Signal sig(
        {BacktestStats? b,
        bool mlApproved = false,
        double? mlProb,
        double entry = 100,
        double sl = 96}) =>
    Signal(
      symbol: 'BTCUSDT',
      timeframe: '4h',
      side: 'LONG',
      time: 't',
      explanation: '',
      score: 60,
      entry: entry,
      sl: sl,
      tp1: 104,
      tp2: 112,
      riskPct: 4,
      backtest: b ?? stats(),
      mlProb: mlProb,
      mlApproved: mlApproved,
      strategy: 'شکست کانال (Donchian)',
    );

AnalyzeResult res({bool edge = false, String note = '', Signal? signal}) =>
    AnalyzeResult(
      symbol: 'ETHUSDT',
      timeframe: '1h',
      candles: 5000,
      edgeOk: edge,
      backtest: stats(t: -1.0, exp: -0.2, pf: 0.7),
      signal: signal,
      note: note,
    );

void main() {
  test('no reliable edge -> avoid, with failing checks', () {
    final d = decisionForResult(res(edge: false));
    expect(d.verdict, Verdict.avoid);
    expect(d.title, 'ورود نکنید');
    expect(d.checks.any((c) => c.ok == false), true);
    expect(d.strength, isEmpty);
  });

  test('edge ok but no entry now -> wait', () {
    final d = decisionForResult(res(edge: true));
    expect(d.verdict, Verdict.wait);
    expect(d.title, 'صبر کنید');
  });

  test('edge ok but rejected (ML/cost) -> wait and shows the note', () {
    final d = decisionForResult(res(edge: true, note: 'رد شد چون ...'));
    expect(d.verdict, Verdict.wait);
    expect(d.subtitle, 'رد شد چون ...');
  });

  test('a signal -> enter, through both entry points', () {
    expect(decisionForSignal(sig()).verdict, Verdict.enter);
    expect(decisionForResult(res(edge: true, signal: sig())).verdict, Verdict.enter);
  });

  test('evidence strength combines t-stat, trades and ML approval', () {
    expect(strengthOf(stats(t: 3.5, trades: 60), mlApproved: true), 'قوی');
    expect(strengthOf(stats(t: 2.4, trades: 30), mlApproved: true), 'متوسط');
    expect(strengthOf(stats(t: 1.6, trades: 25), mlApproved: false), 'ضعیف');
  });

  test('cost check fails for a tight stop', () {
    final d = decisionForSignal(sig(entry: 100, sl: 99.5));
    final cost = d.checks.firstWhere((c) => c.label.startsWith('هزینه'));
    expect(cost.ok, false);
    final fine = decisionForSignal(sig(entry: 100, sl: 96));
    expect(fine.checks.firstWhere((c) => c.label.startsWith('هزینه')).ok, true);
  });

  test('ML check states: untrained, informational, approved', () {
    CheckItem ml(Signal s) =>
        decisionForSignal(s).checks.firstWhere((c) => c.label.contains('یادگیری'));
    expect(ml(sig()).ok, isNull);
    expect(ml(sig(mlProb: 0.6)).ok, isNull);
    expect(ml(sig(mlProb: 0.6, mlApproved: true)).ok, true);
  });

  test('AI prompts carry the app decision so AI cannot contradict it', () {
    expect(buildPrompt(sig()), contains('تصمیم اپ'));
    expect(buildPrompt(sig()), contains('شرایط ورود برقرار است'));
    expect(buildStatePrompt(res(edge: false)), contains('ورود نکنید'));
  });

  group('parseAiBrief', () {
    test('plain JSON', () {
      final b = parseAiBrief(
          '{"reasons":["الف","ب"],"risks":["ج"],"invalidation":"د"}')!;
      expect(b.reasons, ['الف', 'ب']);
      expect(b.risks, ['ج']);
      expect(b.invalidation, 'د');
    });

    test('inside a code fence and with extra text', () {
      final b = parseAiBrief(
          'نتیجه:\n```json\n{"reasons":["الف"],"risks":[],"invalidation":"د"}\n```\nتمام')!;
      expect(b.reasons, ['الف']);
      expect(b.invalidation, 'د');
    });

    test('limits the number of items', () {
      final b = parseAiBrief(
          '{"reasons":["1","2","3","4","5"],"risks":["1","2","3"],"invalidation":""}')!;
      expect(b.reasons.length, 3);
      expect(b.risks.length, 2);
    });

    test('garbage and empty content give null', () {
      expect(parseAiBrief('متن آزاد بدون ساختار'), isNull);
      expect(parseAiBrief('{"reasons":[],"risks":[],"invalidation":""}'), isNull);
      expect(parseAiBrief('{ not valid json }'), isNull);
    });
  });

  test('low timeframes are flagged because costs eat the edge', () {
    final low = decisionForResult(res(edge: true)); // تایم‌فریم 1h
    expect(low.checks.firstWhere((c) => c.label.contains('تایم‌فریم')).ok, false);
    final high = decisionForSignal(sig()); // تایم‌فریم 4h
    expect(high.checks.firstWhere((c) => c.label.contains('تایم‌فریم')).ok, true);
  });
}
