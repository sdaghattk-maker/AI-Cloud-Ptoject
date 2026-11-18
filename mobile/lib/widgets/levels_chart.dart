import 'package:flutter/material.dart';
import '../models/signal.dart';

/// نمایش بصری ورود / حد ضرر / اهداف سود
class LevelsChart extends StatelessWidget {
  const LevelsChart({super.key, required this.signal});
  final Signal signal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      width: double.infinity,
      child: CustomPaint(painter: _LevelsPainter(signal)),
    );
  }
}

class _LevelsPainter extends CustomPainter {
  _LevelsPainter(this.s);
  final Signal s;

  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFD64545);
  static const _blue = Color(0xFF3B82F6);

  @override
  void paint(Canvas canvas, Size size) {
    final vals = [s.entry, s.sl, s.tp1, s.tp2];
    final hi = vals.reduce((a, b) => a > b ? a : b);
    final lo = vals.reduce((a, b) => a < b ? a : b);
    final pad = (hi - lo) * 0.12;
    final range = (hi - lo) + 2 * pad;
    double y(double v) => size.height * (1 - (v - (lo - pad)) / range);

    final profit = Paint()..color = _green.withAlpha(40);
    final loss = Paint()..color = _red.withAlpha(40);
    canvas.drawRect(
        Rect.fromPoints(Offset(0, y(s.entry)), Offset(size.width, y(s.tp2))),
        profit);
    canvas.drawRect(
        Rect.fromPoints(Offset(0, y(s.entry)), Offset(size.width, y(s.sl))),
        loss);

    void line(String label, double v, Color c, {bool bold = false}) {
      final p = Paint()
        ..color = c
        ..strokeWidth = bold ? 2.5 : 1.5;
      canvas.drawLine(Offset(0, y(v)), Offset(size.width, y(v)), p);
      final tp = TextPainter(
        text: TextSpan(
          text: '$label  ${fmt(v)}',
          style: TextStyle(
              color: c, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dy = y(v) - tp.height - 2;
      tp.paint(canvas, Offset(6, dy < 0 ? y(v) + 2 : dy));
    }

    line('TP2', s.tp2, _green);
    line('TP1', s.tp1, _green);
    line('Entry', s.entry, _blue, bold: true);
    line('SL', s.sl, _red);
  }

  @override
  bool shouldRepaint(covariant _LevelsPainter old) => old.s != s;
}
