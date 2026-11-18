import 'package:flutter/material.dart';
import '../models/signal.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.stats, this.title = 'نتیجه بک‌تست (خارج از نمونه)'});
  final BacktestStats stats;
  final String title;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value) => Expanded(
          child: Column(children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            cell('معاملات', '${stats.trades}'),
            cell('وین‌ریت', '${stats.winRate}٪'),
            cell('میانگین R', '${stats.expectancyR}'),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            cell('Profit Factor', '${stats.profitFactor}'),
            cell('بیشینه افت', '${stats.maxDdR}R'),
            cell('مجموع R', '${stats.totalR}'),
          ]),
        ]),
      ),
    );
  }
}
