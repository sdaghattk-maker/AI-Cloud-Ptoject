import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../engine/chart_data.dart';
import '../models/signal.dart';

class ChartOptions {
  final bool ema50, ema200, bb, volume, rsi, markers, levels;
  const ChartOptions({
    this.ema50 = true,
    this.ema200 = true,
    this.bb = false,
    this.volume = true,
    this.rsi = true,
    this.markers = true,
    this.levels = true,
  });

  ChartOptions copyWith({
    bool? ema50,
    bool? ema200,
    bool? bb,
    bool? volume,
    bool? rsi,
    bool? markers,
    bool? levels,
  }) =>
      ChartOptions(
        ema50: ema50 ?? this.ema50,
        ema200: ema200 ?? this.ema200,
        bb: bb ?? this.bb,
        volume: volume ?? this.volume,
        rsi: rsi ?? this.rsi,
        markers: markers ?? this.markers,
        levels: levels ?? this.levels,
      );
}

const _axisW = 58.0;
const _timeH = 20.0;
const _gap = 6.0;

int _future(int count) => math.max(4, (count * 0.15).round());

double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// چارت کندلی: جابه‌جایی با کشیدن، زوم با دو انگشت، لمس برای کراس‌هیر
class CandleChart extends StatefulWidget {
  const CandleChart({
    super.key,
    required this.data,
    required this.overlays,
    required this.options,
  });
  final ChartData data;
  final List<LevelOverlay> overlays;
  final ChartOptions options;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  late int _count;
  int _baseCount = 110;
  double _offset = 0; // تعداد کندل‌های پنهان در سمت راست (0 = آخرین کندل)
  int? _cross;

  @override
  void initState() {
    super.initState();
    _count = math.min(110, math.max(20, widget.data.length));
  }

  int _maxCount(int n) => math.max(20, math.min(400, n));

  ({int start, int end}) _range() {
    final n = widget.data.length;
    final count = math.min(_count, n);
    final maxOffset = math.max(0, n - count).toDouble();
    final off = _clampD(_offset, 0.0, maxOffset).round();
    final end = n - off;
    return (start: end - count, end: end);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final n = widget.data.length;
    if (n == 0) return const Center(child: Text('داده‌ای برای نمایش نیست'));

    return LayoutBuilder(builder: (context, cons) {
      final size = Size(cons.maxWidth, cons.maxHeight);
      final r = _range();
      final slotW = (size.width - _axisW) / ((r.end - r.start) + _future(r.end - r.start));

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _baseCount = _count,
        onScaleUpdate: (d) {
          setState(() {
            if (d.pointerCount > 1 && d.scale != 1.0) {
              _count = math.max(20, math.min(_maxCount(n), (_baseCount / d.scale).round()));
            }
            final sw = (size.width - _axisW) / (_count + _future(_count));
            _offset += d.focalPointDelta.dx / sw;
            _offset = _clampD(_offset, 0.0, math.max(0, n - _count).toDouble());
          });
        },
        onTapUp: (d) {
          final rr = _range();
          if (d.localPosition.dx > size.width - _axisW) return;
          final idx = rr.start + (d.localPosition.dx / slotW - 0.5).round();
          final clamped = math.max(rr.start, math.min(rr.end - 1, idx));
          setState(() => _cross = (_cross == clamped) ? null : clamped);
        },
        child: CustomPaint(
          size: size,
          painter: _ChartPainter(
            data: widget.data,
            start: r.start,
            end: r.end,
            options: widget.options,
            overlays: widget.overlays,
            cross: _cross,
            dark: dark,
          ),
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.data,
    required this.start,
    required this.end,
    required this.options,
    required this.overlays,
    required this.cross,
    required this.dark,
  });

  final ChartData data;
  final int start, end;
  final ChartOptions options;
  final List<LevelOverlay> overlays;
  final int? cross;
  final bool dark;

  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFD64545);
  static const _blue = Color(0xFF3B82F6);
  static const _orange = Color(0xFFF59E0B);
  static const _purple = Color(0xFFA78BFA);

  Color get _text => dark ? Colors.white70 : Colors.black87;
  Color get _grid => dark ? Colors.white12 : Colors.black12;

  void _label(Canvas canvas, String s, Offset o,
      {Color? color, double size = 10, bool bold = false, bool right = false, Color? bg}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color ?? _text,
              fontSize: size,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = right ? o.dx - tp.width : o.dx;
    if (bg != null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(dx - 3, o.dy - 1, tp.width + 6, tp.height + 2),
              const Radius.circular(3)),
          Paint()..color = bg);
    }
    tp.paint(canvas, Offset(dx, o.dy));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p,
      {double dash = 6, double gapLen = 4}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final e = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * e, p);
      d += dash + gapLen;
    }
  }

  void _axisChip(Canvas canvas, double plotW, double y, String text, Color color) {
    final rect = Rect.fromLTWH(plotW + 1, y - 7, _axisW - 2, 14);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = color);
    _label(canvas, text, Offset(plotW + 4, y - 6), color: Colors.white, size: 8.5, bold: true);
  }

  String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    if (data.timeframe == '1d') return '${two(d.month)}/${two(d.day)}';
    return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final count = end - start;
    if (count <= 0) return;
    final future = _future(count);
    final plotW = size.width - _axisW;
    final slotW = plotW / (count + future);
    double xAt(int i) => (i - start + 0.5) * slotW;

    // ----- چیدمان پنل‌ها -----
    final showVol = options.volume, showRsi = options.rsi;
    final gaps = (showVol ? 1 : 0) + (showRsi ? 1 : 0);
    final avail = size.height - _timeH - _gap * gaps;
    final wTotal = 1.0 + (showVol ? 0.22 : 0) + (showRsi ? 0.35 : 0);
    final hPrice = avail / wTotal;
    final priceRect = Rect.fromLTWH(0, 0, plotW, hPrice);
    var top = hPrice;
    Rect? volRect, rsiRect;
    if (showVol) {
      top += _gap;
      volRect = Rect.fromLTWH(0, top, plotW, avail * 0.22 / wTotal);
      top = volRect.bottom;
    }
    if (showRsi) {
      top += _gap;
      rsiRect = Rect.fromLTWH(0, top, plotW, avail * 0.35 / wTotal);
      top = rsiRect.bottom;
    }

    // ----- محدوده قیمت (شامل سطوح معامله) -----
    var lo = double.infinity, hi = -double.infinity;
    for (var i = start; i < end; i++) {
      lo = math.min(lo, data.low[i]);
      hi = math.max(hi, data.high[i]);
    }
    for (final o in overlays) {
      for (final v in [o.entry, o.sl, o.tp2]) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    final pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;
    if (hi - lo <= 0) hi = lo + 1;
    double yP(double v) => priceRect.top + (hi - v) / (hi - lo) * priceRect.height;

    // ----- شبکه و برچسب قیمت -----
    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final price = hi - (hi - lo) * g / 4;
      final y = yP(price);
      canvas.drawLine(Offset(0, y), Offset(plotW, y), gridPaint);
      _label(canvas, fmt(price), Offset(plotW + 4, y - 6), size: 9);
    }

    // ----- محتوای پنل قیمت (با clip) -----
    canvas.save();
    canvas.clipRect(priceRect);

    // سطوح حمایت/مقاومت
    if (options.levels) {
      for (final l in data.levels) {
        if (l.price < lo || l.price > hi) continue;
        final c = (l.resistance ? _red : _green).withAlpha(150);
        _dashed(canvas, Offset(0, yP(l.price)), Offset(plotW, yP(l.price)),
            Paint()
              ..color = c
              ..strokeWidth = 1,
            dash: 3,
            gapLen: 4);
        _label(canvas, '${l.resistance ? 'R' : 'S'}×${l.touches}',
            Offset(4, yP(l.price) - 11),
            color: c, size: 9, bold: true);
      }
    }

    // باند بولینگر
    if (options.bb) {
      _poly(canvas, data.bbUp, Paint()
        ..color = _purple.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1, yP, xAt);
      _poly(canvas, data.bbLo, Paint()
        ..color = _purple.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1, yP, xAt);
    }

    // کندل‌ها
    final bodyW = math.max(1.0, slotW * 0.7);
    for (var i = start; i < end; i++) {
      final up = data.close[i] >= data.open[i];
      final color = up ? _green : _red;
      final x = xAt(i);
      final p = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, yP(data.high[i])), Offset(x, yP(data.low[i])), p);
      final yTop = yP(math.max(data.open[i], data.close[i]));
      final yBot = yP(math.min(data.open[i], data.close[i]));
      canvas.drawRect(
          Rect.fromLTRB(x - bodyW / 2, yTop, x + bodyW / 2, math.max(yBot, yTop + 1)),
          Paint()..color = color);
    }

    // EMAها
    if (options.ema200) {
      _poly(canvas, data.ema200, Paint()
        ..color = _orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4, yP, xAt);
    }
    if (options.ema50) {
      _poly(canvas, data.ema50, Paint()
        ..color = _blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4, yP, xAt);
    }

    // ناحیه‌ها و خطوط ورود / SL / TP
    for (final o in overlays) {
      final x0 = math.max(0.0, xAt(o.startIndex));
      canvas.drawRect(Rect.fromPoints(Offset(x0, yP(o.entry)), Offset(plotW, yP(o.tp2))),
          Paint()..color = _green.withAlpha(36));
      canvas.drawRect(Rect.fromPoints(Offset(x0, yP(o.entry)), Offset(plotW, yP(o.sl))),
          Paint()..color = _red.withAlpha(36));
      void level(double v, Color c, double w) {
        final p = Paint()
          ..color = c
          ..strokeWidth = w;
        if (o.dashed) {
          _dashed(canvas, Offset(x0, yP(v)), Offset(plotW, yP(v)), p);
        } else {
          canvas.drawLine(Offset(x0, yP(v)), Offset(plotW, yP(v)), p);
        }
      }

      level(o.tp2, _green, 1.6);
      level(o.tp1, _green.withAlpha(170), 1.2);
      level(o.entry, _blue, 1.8);
      level(o.sl, _red, 1.6);
    }

    // علامت معاملات تاریخی استراتژی منتخب
    if (options.markers) {
      for (final m in data.markers) {
        if (m.index < start || m.index >= end) continue;
        final x = xAt(m.index);
        final c = m.r > 0 ? _green : _red;
        final path = Path();
        if (m.side == 1) {
          final y = yP(data.low[m.index]) + 9;
          path
            ..moveTo(x, y - 6)
            ..lineTo(x - 5, y + 3)
            ..lineTo(x + 5, y + 3)
            ..close();
          if (slotW >= 14) {
            _label(canvas, m.r.toStringAsFixed(1), Offset(x - 8, y + 5), color: c, size: 8);
          }
        } else {
          final y = yP(data.high[m.index]) - 9;
          path
            ..moveTo(x, y + 6)
            ..lineTo(x - 5, y - 3)
            ..lineTo(x + 5, y - 3)
            ..close();
          if (slotW >= 14) {
            _label(canvas, m.r.toStringAsFixed(1), Offset(x - 8, y - 16), color: c, size: 8);
          }
        }
        canvas.drawPath(path, Paint()..color = c);
      }
    }
    canvas.restore();

    // ----- چیپ‌های محور برای سطوح معامله و قیمت آخر -----
    for (final o in overlays) {
      void chip(String t, double v, Color c) {
        final y = yP(v);
        if (y < priceRect.top || y > priceRect.bottom) return;
        _axisChip(canvas, plotW, y, t, c);
      }

      chip('T2 ${fmt(o.tp2)}', o.tp2, _green);
      chip('T1 ${fmt(o.tp1)}', o.tp1, _green.withAlpha(200));
      chip('E ${fmt(o.entry)}', o.entry, _blue);
      chip('SL ${fmt(o.sl)}', o.sl, _red);
    }
    final lastClose = data.close[end - 1];
    final lastUp = lastClose >= data.open[end - 1];
    final yLast = yP(lastClose);
    canvas.save();
    canvas.clipRect(priceRect);
    _dashed(canvas, Offset(0, yLast), Offset(plotW, yLast),
        Paint()
          ..color = (lastUp ? _green : _red).withAlpha(200)
          ..strokeWidth = 1,
        dash: 2,
        gapLen: 3);
    canvas.restore();
    if (overlays.isEmpty) {
      _axisChip(canvas, plotW, yLast, fmt(lastClose), lastUp ? _green : _red);
    }

    // ----- حجم -----
    final volBox = volRect;
    if (volBox != null) {
      var maxV = 0.0;
      for (var i = start; i < end; i++) {
        maxV = math.max(maxV, data.volume[i]);
      }
      if (maxV > 0) {
        for (var i = start; i < end; i++) {
          final up = data.close[i] >= data.open[i];
          final h = data.volume[i] / maxV * volBox.height;
          canvas.drawRect(
              Rect.fromLTRB(xAt(i) - bodyW / 2, volBox.bottom - h, xAt(i) + bodyW / 2,
                  volBox.bottom),
              Paint()..color = (up ? _green : _red).withAlpha(120));
        }
      }
      _label(canvas, 'Vol', Offset(4, volBox.top + 1), size: 9);
    }

    // ----- RSI -----
    final rsiBox = rsiRect;
    if (rsiBox != null) {
      double yR(double v) => rsiBox.top + (100 - v) / 100 * rsiBox.height;
      for (final level in const [30.0, 50.0, 70.0]) {
        _dashed(canvas, Offset(0, yR(level)), Offset(plotW, yR(level)),
            Paint()
              ..color = _grid
              ..strokeWidth = 1,
            dash: 3,
            gapLen: 3);
        if (level != 50) {
          _label(canvas, level.toInt().toString(), Offset(plotW + 4, yR(level) - 6), size: 9);
        }
      }
      canvas.save();
      canvas.clipRect(rsiBox);
      _poly(canvas, data.rsi, Paint()
        ..color = _purple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3, yR, xAt);
      canvas.restore();
      _label(canvas, 'RSI ${data.rsi[end - 1].toStringAsFixed(0)}',
          Offset(4, rsiBox.top + 1),
          size: 9, color: _purple);
    }

    // ----- محور زمان -----
    final step = math.max(1, (72 / slotW).ceil());
    for (var i = start; i < end; i += step) {
      _label(canvas, _fmtTime(data.times[i]), Offset(xAt(i) - 24, size.height - _timeH + 4),
          size: 9);
    }

    // ----- راهنما -----
    var lx = 6.0;
    void legend(String t, Color c) {
      _label(canvas, t, Offset(lx, 3), color: c, size: 9, bold: true);
      lx += t.length * 6.0 + 10;
    }

    if (options.ema50) legend('EMA50', _blue);
    if (options.ema200) legend('EMA200', _orange);
    if (options.bb) legend('BB', _purple);

    // ----- کراس‌هیر -----
    final ci = cross;
    if (ci != null && ci >= start && ci < end) {
      final x = xAt(ci);
      final p = Paint()
        ..color = _text.withAlpha(120)
        ..strokeWidth = 1;
      _dashed(canvas, Offset(x, 0), Offset(x, size.height - _timeH), p, dash: 3, gapLen: 3);
      _dashed(canvas, Offset(0, yP(data.close[ci])), Offset(plotW, yP(data.close[ci])), p,
          dash: 3, gapLen: 3);
      final lines = <String>[
        _fmtTime(data.times[ci]),
        'O ${fmt(data.open[ci])}   H ${fmt(data.high[ci])}',
        'L ${fmt(data.low[ci])}   C ${fmt(data.close[ci])}',
        'Vol ${data.volume[ci].toStringAsFixed(0)}   RSI ${data.rsi[ci].toStringAsFixed(0)}',
        'EMA50 ${fmt(data.ema50[ci])}   EMA200 ${fmt(data.ema200[ci])}',
      ];
      final bg = dark ? const Color(0xE6161B22) : const Color(0xE6FFFFFF);
      const boxW = 190.0;
      final boxX = x > plotW / 2 ? 6.0 : plotW - boxW - 6;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(boxX, 18, boxW, 14.0 * lines.length + 8), const Radius.circular(6)),
          Paint()..color = bg);
      for (var k = 0; k < lines.length; k++) {
        _label(canvas, lines[k], Offset(boxX + 6, 22 + 14.0 * k), size: 10);
      }
    }
  }

  void _poly(Canvas canvas, List<double> v, Paint p, double Function(double) y,
      double Function(int) x) {
    final path = Path();
    var pen = false;
    for (var i = start; i < end; i++) {
      final val = v[i];
      if (val.isNaN) {
        pen = false;
        continue;
      }
      final px = x(i), py = y(val);
      if (!pen) {
        path.moveTo(px, py);
        pen = true;
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
