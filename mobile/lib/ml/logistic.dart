import 'dart:math' as math;

/// رگرسیون لجستیک ساده با نرمال‌سازی و جریمه L2 (سبک و مناسب اجرا روی گوشی)
class LogisticModel {
  final List<double> mean, std, w;
  final double b;
  const LogisticModel(this.mean, this.std, this.w, this.b);

  double predict(List<double> x) {
    var z = b;
    for (var j = 0; j < w.length; j++) {
      z += w[j] * (x[j] - mean[j]) / std[j];
    }
    return 1 / (1 + math.exp(-z));
  }

  Map<String, dynamic> toJson() => {'mean': mean, 'std': std, 'w': w, 'b': b};

  factory LogisticModel.fromJson(Map<String, dynamic> j) {
    List<double> l(dynamic v) =>
        (v as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    return LogisticModel(l(j['mean']), l(j['std']), l(j['w']), (j['b'] as num).toDouble());
  }
}

LogisticModel? trainLogistic(List<List<double>> x, List<int> y,
    {int epochs = 300, double lr = 0.3, double l2 = 0.1}) {
  final n = x.length;
  if (n < 2) return null;
  final ones = y.where((v) => v == 1).length;
  if (ones == 0 || ones == n) return null; // فقط یک کلاس

  final m = x.first.length;
  final mean = List<double>.filled(m, 0);
  final std = List<double>.filled(m, 1);
  for (var j = 0; j < m; j++) {
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += x[i][j];
    }
    mean[j] = s / n;
    var v = 0.0;
    for (var i = 0; i < n; i++) {
      final d = x[i][j] - mean[j];
      v += d * d;
    }
    final sd = math.sqrt(v / n);
    std[j] = sd < 1e-9 ? 1.0 : sd;
  }
  final z = [
    for (var i = 0; i < n; i++)
      [for (var j = 0; j < m; j++) (x[i][j] - mean[j]) / std[j]]
  ];

  final w = List<double>.filled(m, 0);
  var b = 0.0;
  for (var e = 0; e < epochs; e++) {
    final gw = List<double>.filled(m, 0);
    var gb = 0.0;
    for (var i = 0; i < n; i++) {
      var s = b;
      for (var j = 0; j < m; j++) {
        s += w[j] * z[i][j];
      }
      final err = 1 / (1 + math.exp(-s)) - y[i];
      for (var j = 0; j < m; j++) {
        gw[j] += err * z[i][j];
      }
      gb += err;
    }
    for (var j = 0; j < m; j++) {
      w[j] -= lr * (gw[j] / n + l2 * w[j]);
    }
    b -= lr * gb / n;
  }
  return LogisticModel(mean, std, w, b);
}
