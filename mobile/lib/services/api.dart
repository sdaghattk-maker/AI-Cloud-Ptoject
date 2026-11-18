import '../engine/engine.dart';
import '../models/signal.dart';

export 'errors.dart';

/// دیگر سروری در کار نیست؛ تحلیل مستقیم روی گوشی انجام می‌شود.
class Api {
  Future<List<Signal>> scan({void Function(int done, int total)? onProgress}) =>
      Engine.scan(onProgress: onProgress);

  Future<AnalyzeResult> analyze(String symbol, String tf) =>
      Engine.analyze(symbol, tf);
}
