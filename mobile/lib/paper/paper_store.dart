import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/binance.dart';
import '../models/signal.dart';
import '../services/errors.dart';
import 'paper_trade.dart';

class PaperStore {
  static const _key = 'paper_trades';
  static const maxTrades = 500;

  static Future<List<PaperTrade>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_key) ?? const <String>[];
      return [
        for (final r in raw) PaperTrade.fromJson(jsonDecode(r) as Map<String, dynamic>)
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<PaperTrade> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, [for (final t in list) jsonEncode(t.toJson())]);
  }

  /// ثبت سیگنال (تکراری‌ها نادیده گرفته می‌شوند). true یعنی معامله جدید ثبت شد.
  static Future<bool> record(Signal s) async {
    final t = PaperTrade.fromSignal(s);
    final list = await load();
    if (list.any((x) => x.id == t.id)) return false;
    list.insert(0, t);
    if (list.length > maxTrades) list.removeRange(maxTrades, list.length);
    await save(list);
    return true;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}

class PaperEngine {
  /// معاملات باز را با کندل‌های بسته‌شده جدید به‌روز می‌کند.
  static Future<List<PaperTrade>> refresh({DateTime? now}) async {
    final list = await PaperStore.load();
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;

    final need = <String, int>{};
    for (final t in list) {
      if (t.isClosed) continue;
      final elapsed = ((nowMs - t.signalTimeMs) / tfMs(t.timeframe)).ceil() + 3;
      final k = '${t.symbol}|${t.timeframe}';
      need[k] = math.max(need[k] ?? 0, math.min(1000, math.max(5, elapsed)));
    }

    final fetched = <String, Candles?>{};
    for (final e in need.entries) {
      final parts = e.key.split('|');
      try {
        fetched[e.key] = await Binance.klines(parts[0], parts[1], total: e.value);
      } catch (_) {
        fetched[e.key] = null;
      }
    }
    if (need.isNotEmpty && fetched.values.every((v) => v == null)) {
      throw ApiException('دریافت قیمت‌ها از بایننس ممکن نشد. اینترنت و VPN را بررسی کنید.');
    }

    var changed = false;
    final out = <PaperTrade>[];
    for (final t in list) {
      if (t.isClosed) {
        out.add(t);
        continue;
      }
      final c = fetched['${t.symbol}|${t.timeframe}'];
      if (c == null) {
        out.add(t);
        continue;
      }
      final u = t.withSim(simulatePaper(t, c));
      if (u.status != t.status || u.tp1Hit != t.tp1Hit || u.barsHeld != t.barsHeld) {
        changed = true;
      }
      out.add(u);
    }
    if (changed) await PaperStore.save(out);
    return out;
  }
}
