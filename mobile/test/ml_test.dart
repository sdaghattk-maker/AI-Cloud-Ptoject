import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptosignal/engine/analyzer.dart';
import 'package:cryptosignal/engine/engine.dart';
import 'package:cryptosignal/ml/logistic.dart';
import 'package:cryptosignal/ml/ml_filter.dart';
import 'package:cryptosignal/models/signal.dart';
import 'package:cryptosignal/services/errors.dart';
import 'package:cryptosignal/services/llm.dart';
import 'package:cryptosignal/services/settings.dart';

List<TradeSample> makeSamples(int n, int seed, {required bool informative}) {
  final rnd = Random(seed);
  double gauss() {
    final u1 = 1 - rnd.nextDouble();
    final u2 = rnd.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  final out = <TradeSample>[];
  for (var i = 0; i < n; i++) {
    final x = List<double>.generate(8, (_) => gauss());
    final p = informative ? 1 / (1 + exp(-(1.6 * x[0] - 1.2 * x[3]))) : 0.4;
    final win = rnd.nextDouble() < p;
    out.add(TradeSample(
        timeMs: i * 1000, endMs: i * 1000 + 300, x: x, r: win ? 1.8 : -1.0));
  }
  return out;
}

Signal sampleSignal() => Signal.fromJson({
      'symbol': 'BTCUSDT',
      'timeframe': '1h',
      'side': 'LONG',
      'time': '2026-11-17T10:00:00Z',
      'score': 60,
      'entry': 100.0,
      'sl': 96.0,
      'tp1': 104.0,
      'tp2': 112.0,
      'risk_pct': 4.0,
      'backtest': {
        'trades': 30,
        'win_rate': 55.0,
        'expectancy_R': 0.2,
        'profit_factor': 1.4,
        'max_dd_R': 3.0,
        'total_R': 6.0
      },
    });

void main() {
  test('logistic regression separates an easy pattern', () {
    final rnd = Random(1);
    final x = <List<double>>[];
    final y = <int>[];
    for (var i = 0; i < 400; i++) {
      final v = rnd.nextDouble() * 4 - 2;
      x.add([v, rnd.nextDouble()]);
      y.add(v > 0 ? 1 : 0);
    }
    final m = trainLogistic(x, y)!;
    expect(m.predict([1.5, 0.5]), greaterThan(0.8));
    expect(m.predict([-1.5, 0.5]), lessThan(0.2));
  });

  test('trainLogistic returns null for single-class data', () {
    expect(trainLogistic([[1.0], [2.0], [3.0]], [1, 1, 1]), isNull);
  });

  test('too few samples gives no model', () {
    expect(buildMlModel(makeSamples(50, 1, informative: true)), isNull);
  });

  test('informative features are approved and improve expectancy', () {
    final m = buildMlModel(makeSamples(900, 5, informative: true))!;
    expect(m.approved, true);
    expect(m.report.filteredExpectancy, greaterThan(m.report.baseExpectancy));
  });

  test('pure noise is almost never approved', () {
    var approved = 0;
    for (var seed = 0; seed < 10; seed++) {
      final m = buildMlModel(makeSamples(900, seed, informative: false));
      if (m != null && m.approved) approved++;
    }
    expect(approved, lessThanOrEqualTo(2));
  });

  test('model JSON round-trip keeps predictions', () {
    final m = buildMlModel(makeSamples(900, 5, informative: true))!;
    final back = MlModel.fromJson(m.toJson());
    final x = List<double>.filled(8, 0.3);
    expect(back.model.predict(x), closeTo(m.model.predict(x), 1e-12));
    expect(back.approved, m.approved);
  });

  test('applyMl rejects weak signals and keeps strong ones (approved model)', () {
    final model = buildMlModel(makeSamples(900, 5, informative: true))!;
    expect(model.approved, true);
    final base = AnalyzeResult(
        symbol: 'BTCUSDT',
        timeframe: '1h',
        candles: 5000,
        edgeOk: true,
        backtest: sampleSignal().backtest,
        signal: sampleSignal());

    final weakX = [-3.0, 0, 0, 2.0, 0, 0, 0, 0].map((e) => e.toDouble()).toList();
    final strongX = [3.0, 0, 0, -2.0, 0, 0, 0, 0].map((e) => e.toDouble()).toList();

    final weak = Engine.applyMl(SeriesResult(base, const [], weakX), model);
    expect(weak.signal, isNull);
    expect(weak.note, isNotEmpty);

    final strong = Engine.applyMl(SeriesResult(base, const [], strongX), model);
    expect(strong.signal, isNotNull);
    expect(strong.signal!.mlProb, greaterThan(model.threshold));
  });

  test('applyMl without a model keeps the signal and explains', () {
    final base = AnalyzeResult(
        symbol: 'BTCUSDT',
        timeframe: '1h',
        candles: 5000,
        edgeOk: true,
        backtest: sampleSignal().backtest,
        signal: sampleSignal());
    final r = Engine.applyMl(
        SeriesResult(base, const [], List<double>.filled(8, 0)), null);
    expect(r.signal, isNotNull);
    expect(r.signal!.mlStatus, isNotEmpty);
  });

  test('AI prompt contains the signal numbers but asks nothing invented', () {
    final p = buildPrompt(sampleSignal());
    expect(p, contains('BTCUSDT'));
    expect(p, contains('100.00'));
    expect(p, contains('1:3.0'));
  });

  test('state prompt explains a no-signal result without inventing data', () {
    final r = AnalyzeResult(
        symbol: 'ETHUSDT',
        timeframe: '4h',
        candles: 5000,
        edgeOk: false,
        backtest: sampleSignal().backtest,
        signal: null,
        context: const {'lastPrice': 3000.0, 'adx': 18.5});
    final p = buildStatePrompt(r);
    expect(p, contains('ETHUSDT'));
    expect(p, contains('ندارد'));
    expect(p, contains('adx=18.5'));
    expect(p, contains('لبه آماری'));
  });

  test('AiProfile readiness and labels', () {
    expect(const AiProfile().ready, false);
    const g = AiProfile(
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
        model: 'm',
        key: 'k');
    expect(g.ready, true);
    expect(g.label(0), 'Gemini');
    expect(const AiProfile(baseUrl: 'https://api.groq.com/openai/v1').label(1), 'Groq');
    expect(const AiProfile(baseUrl: 'https://x.example').label(1), 'AI 2');
  });

  test('asking AI without any configured profile fails with a clear error', () async {
    Settings.aiProfiles = [const AiProfile(), const AiProfile()];
    await expectLater(
        Llm.ask('k', stateSystemPrompt, 'p'), throwsA(isA<ApiException>()));
  });
}
