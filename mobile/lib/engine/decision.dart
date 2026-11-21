import '../models/signal.dart';
import 'analyzer.dart';
import 'backtest.dart';

/// حکم نهایی اپ؛ بر پایه قوانین قطعی و قابل‌بررسی (نه نظر AI)
enum Verdict { enter, wait, avoid }

class CheckItem {
  final String label, detail;
  final bool? ok; // true ✓ | false ✗ | null = اطلاعاتی
  const CheckItem(this.label, this.ok, this.detail);
}

class Decision {
  final Verdict verdict;
  final String title, subtitle, strength; // strength فقط برای «ورود»
  final List<CheckItem> checks;
  const Decision({
    required this.verdict,
    required this.title,
    required this.subtitle,
    required this.checks,
    this.strength = '',
  });
}

List<CheckItem> _statChecks(BacktestStats b) => [
      CheckItem('میانگین R خارج از نمونه مثبت', b.expectancyR > minOosExpectancy,
          '${b.expectancyR}R'),
      CheckItem('معناداری آماری (t ≥ $minOosTStat)', b.tStat >= minOosTStat,
          't=${b.tStat}'),
      CheckItem('معاملات کافی (≥ $minOosTrades)', b.trades >= minOosTrades,
          '${b.trades} معامله'),
      CheckItem('Profit Factor ≥ $minProfitFactor', b.profitFactor >= minProfitFactor,
          '${b.profitFactor}'),
    ];

/// قدرت شواهد آماری: ترکیب معناداری t، تعداد معاملات و تأیید ML
String strengthOf(BacktestStats b, {required bool mlApproved}) {
  var pts = 0;
  if (b.tStat >= 3) {
    pts += 2;
  } else if (b.tStat >= 2) {
    pts += 1;
  }
  if (b.trades >= 50) pts += 1;
  if (mlApproved) pts += 1;
  if (pts >= 3) return 'قوی';
  if (pts == 2) return 'متوسط';
  return 'ضعیف';
}

/// ۱۵ دقیقه و ۱ ساعت: هزینه رفت‌وبرگشت در بک‌تست ۰.۱۶ تا ۰.۲۰R بود و هر لبه‌ای را می‌خورد
bool _lowTf(String tf) => tf == '15m' || tf == '1h';

CheckItem _tfCheck(String tf) => CheckItem(
    'تایم‌فریم ۴ ساعته یا بالاتر (هزینه کمتر)', !_lowTf(tf), tf);

Decision decisionForSignal(Signal s) {
  final b = s.backtest;
  final cost = costInR(s.entry, s.riskDistance);
  final ml = s.mlProb == null
      ? const CheckItem('فیلتر یادگیری ماشین', null, 'هنوز آموزش ندیده')
      : CheckItem(
          'فیلتر یادگیری ماشین',
          s.mlApproved ? true : null,
          s.mlApproved
              ? 'احتمال ${(s.mlProb! * 100).round()}٪ (تأیید)'
              : 'فقط اطلاعاتی · احتمال ${(s.mlProb! * 100).round()}٪',
        );
  return Decision(
    verdict: Verdict.enter,
    title: 'شرایط ورود برقرار است',
    subtitle: '${s.isLong ? 'خرید (Long)' : 'فروش (Short)'}'
        '${s.strategy.isEmpty ? '' : ' · ${s.strategy}'}',
    strength: strengthOf(b, mlApproved: s.mlApproved),
    checks: [
      ..._statChecks(b),
      CheckItem('هزینه کارمزد قابل‌قبول (≤ ${(maxCostR * 100).round()}٪ ریسک)',
          cost <= maxCostR, '${(cost * 100).round()}٪ ریسک'),
      _tfCheck(s.timeframe),
      const CheckItem('شرط ورود در کندل فعلی', true, 'برقرار'),
      ml,
    ],
  );
}

Decision decisionForResult(AnalyzeResult r) {
  final sig = r.signal;
  if (sig != null) return decisionForSignal(sig);

  final checks = [
    ..._statChecks(r.backtest),
    _tfCheck(r.timeframe),
    CheckItem('شرط ورود در کندل فعلی', false,
        r.note.isNotEmpty ? 'رد شد' : 'کامل نیست'),
  ];
  if (!r.edgeOk) {
    return Decision(
      verdict: Verdict.avoid,
      title: 'ورود نکنید',
      subtitle: 'در بک‌تست خارج از نمونه، هیچ‌کدام از ۳ استراتژی روی این نماد '
          'لبه قابل‌اعتماد نشان نداده‌اند.',
      checks: checks,
    );
  }
  return Decision(
    verdict: Verdict.wait,
    title: 'صبر کنید',
    subtitle: r.note.isNotEmpty
        ? r.note
        : 'آمار بک‌تست قابل‌قبول است ولی شرط ورود در کندل فعلی کامل نیست.',
    checks: checks,
  );
}
