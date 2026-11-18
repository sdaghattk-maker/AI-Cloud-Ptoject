import 'package:flutter/material.dart';
import '../models/signal.dart';

/// محاسبه حجم پوزیشن بر اساس درصد ریسک از سرمایه
class RiskCalculator extends StatefulWidget {
  const RiskCalculator({super.key, required this.signal});
  final Signal signal;

  @override
  State<RiskCalculator> createState() => _RiskCalculatorState();
}

class _RiskCalculatorState extends State<RiskCalculator> {
  final _capital = TextEditingController(text: '1000');
  final _risk = TextEditingController(text: '1');

  @override
  void dispose() {
    _capital.dispose();
    _risk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cap = double.tryParse(_capital.text) ?? 0;
    final pct = double.tryParse(_risk.text) ?? 0;
    final dist = widget.signal.riskDistance;
    final riskAmount = cap * pct / 100;
    final units = dist > 0 ? riskAmount / dist : 0.0;
    final notional = units * widget.signal.entry;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ماشین‌حساب مدیریت ریسک',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _capital,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'سرمایه (USDT)', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _risk,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'ریسک هر معامله (٪)',
                    border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text('حداکثر ضرر در صورت فعال‌شدن SL: ${riskAmount.toStringAsFixed(2)} USDT'),
          Text('حجم پوزیشن: ${units.toStringAsFixed(6)} ${widget.signal.symbol.replaceAll('USDT', '')}'),
          Text('ارزش پوزیشن: ${notional.toStringAsFixed(2)} USDT'),
        ]),
      ),
    );
  }
}
