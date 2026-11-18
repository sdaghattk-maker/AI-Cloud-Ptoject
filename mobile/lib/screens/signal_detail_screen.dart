import 'package:flutter/material.dart';
import '../models/signal.dart';
import '../widgets/signal_body.dart';

class SignalDetailScreen extends StatelessWidget {
  const SignalDetailScreen({super.key, required this.signal});
  final Signal signal;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(signal.symbol)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [SignalBody(signal: signal)],
      ),
    );
  }
}
