import 'package:flutter/material.dart';
import '../models/signal.dart';
import '../widgets/signal_body.dart';
import 'chart_screen.dart';

class SignalDetailScreen extends StatelessWidget {
  const SignalDetailScreen({super.key, required this.signal});
  final Signal signal;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(signal.symbol),
        actions: [
          IconButton(
            tooltip: 'نمایش روی چارت',
            icon: const Icon(Icons.show_chart),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ChartScreen(symbol: signal.symbol, timeframe: signal.timeframe))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [SignalBody(signal: signal)],
      ),
    );
  }
}
