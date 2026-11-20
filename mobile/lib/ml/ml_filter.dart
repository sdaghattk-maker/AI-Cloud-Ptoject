import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'logistic.dart';

class TradeSample {
  final int timeMs, endMs; // زمان سیگنال و زمان بسته‌شدن معامله
  final List<double> x;
  final double r; // نتیجه خالص بر حسب R
  final int side, strategy; // +1/-1 و ۰/۱/۲ (برای گزارش پژوهشی)
  const TradeSample({
    required this.timeMs,
    required this.endMs,
    required this.x,
    required this.r,
    this.side = 0,
    this.strategy = 0,
  });
}

class MlReport {
  final int samples, oosTrades, filteredTrades;
  final double baseExpectancy, filteredExpectancy, tStat;
  final bool approved;
  const MlReport({
    required this.samples,
    required this.oosTrades,
    required this.filteredTrades,
    required this.baseExpectancy,
    required this.filteredExpectancy,
    required this.tStat,
    required this.approved,
  });

  Map<String, dynamic> toJson() => {
        'samples': samples,
        'oosTrades': oosTrades,
        'filteredTrades': filteredTrades,
        'baseExpectancy': baseExpectancy,
        'filteredExpectancy': filteredExpectancy,
        'tStat': tStat,
        'approved': approved,
      };

  factory MlReport.fromJson(Map<String, dynamic> j) => MlReport(
        samples: (j['samples'] as num).toInt(),
        oosTrades: (j['oosTrades'] as num).toInt(),
        filteredTrades: (j['filteredTrades'] as num).toInt(),
        baseExpectancy: (j['baseExpectancy'] as num).toDouble(),
        filteredExpectancy: (j['filteredExpectancy'] as num).toDouble(),
        tStat: (j['tStat'] as num).toDouble(),
        approved: j['approved'] as bool,
      );
}

class MlModel {
  final LogisticModel model;
  final double threshold;
  final MlReport report;
  final int trainedAtMs;
  const MlModel(this.model, this.threshold, this.report, this.trainedAtMs);

  bool get approved => report.approved;

  Map<String, dynamic> toJson() => {
        'v': 2,
        'model': model.toJson(),
        'threshold': threshold,
        'report': report.toJson(),
        'trainedAtMs': trainedAtMs,
      };

  factory MlModel.fromJson(Map<String, dynamic> j) {
    if (j['v'] != 2) throw const FormatException('old ML model version');
    return MlModel(
        LogisticModel.fromJson(j['model'] as Map<String, dynamic>),
        (j['threshold'] as num).toDouble(),
        MlReport.fromJson(j['report'] as Map<String, dynamic>),
        (j['trainedAtMs'] as num).toInt(),
      );
  }
}

double _mean(List<double> v) =>
    v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

double _variance(List<double> v) {
  if (v.length < 2) return 0;
  final m = _mean(v);
  var s = 0.0;
  for (final x in v) {
    s += (x - m) * (x - m);
  }
  return s / (v.length - 1);
}

/// آموزش + ارزیابی Walk-Forward زمانی روی معاملات تاریخی (ترکیب چند نماد).
/// مدل فقط وقتی «تأیید» می‌شود که روی داده‌های دیده‌نشده برتری معنادار آماری نشان دهد.
MlModel? buildMlModel(List<TradeSample> all) {
  if (all.length < 80) return null;
  final s = [...all]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  const chunks = 6;
  final bounds = List<int>.generate(chunks + 1, (k) => (s.length * k / chunks).floor());

  final oos = <double>[], filt = <double>[], rej = <double>[];
  for (var j = 2; j < chunks; j++) {
    final testStart = s[bounds[j]].timeMs;
    // embargo: معاملاتی که نتیجه‌شان به بازه تست رسیده در آموزش نمی‌آیند
    final train = s.sublist(0, bounds[j]).where((t) => t.endMs < testStart).toList();
    final test = s.sublist(bounds[j], bounds[j + 1]);
    if (train.length < 50) continue;
    final m = trainLogistic(
        train.map((t) => t.x).toList(), train.map((t) => t.r > 0 ? 1 : 0).toList());
    if (m == null) continue;
    final thr = train.where((t) => t.r > 0).length / train.length;
    for (final t in test) {
      oos.add(t.r);
      if (m.predict(t.x) >= thr) {
        filt.add(t.r);
      } else {
        rej.add(t.r);
      }
    }
  }

  final base = _mean(oos);
  final fe = _mean(filt);
  var tStat = 0.0;
  if (filt.length >= 2 && rej.length >= 2) {
    final se = math.sqrt(_variance(filt) / filt.length + _variance(rej) / rej.length);
    tStat = se > 0 ? (fe - _mean(rej)) / se : 0.0;
  }
  final approved = oos.length >= 50 &&
      filt.length >= 30 &&
      fe > 0 &&
      fe > base + 0.05 &&
      tStat >= 2.0;

  final finalModel = trainLogistic(
      s.map((t) => t.x).toList(), s.map((t) => t.r > 0 ? 1 : 0).toList());
  if (finalModel == null) return null;
  final thr = s.where((t) => t.r > 0).length / s.length;

  return MlModel(
    finalModel,
    thr,
    MlReport(
      samples: s.length,
      oosTrades: oos.length,
      filteredTrades: filt.length,
      baseExpectancy: base,
      filteredExpectancy: fe,
      tStat: tStat,
      approved: approved,
    ),
    DateTime.now().millisecondsSinceEpoch,
  );
}

/// ذخیره مدل هر تایم‌فریم روی گوشی (برای تب «تحلیل» که داده یک نماد دارد)
class MlStore {
  static Future<void> save(String tf, MlModel m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ml_$tf', jsonEncode(m.toJson()));
  }

  static Future<MlModel?> load(String tf) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('ml_$tf');
      if (raw == null) return null;
      return MlModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, MlModel>> loadAll(List<String> tfs) async {
    final out = <String, MlModel>{};
    for (final tf in tfs) {
      final m = await load(tf);
      if (m != null) out[tf] = m;
    }
    return out;
  }
}
