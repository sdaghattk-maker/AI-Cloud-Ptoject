import 'package:flutter/material.dart';
import '../engine/decision.dart';

/// کارت تصمیم: حکم اپ + قدرت شواهد + چک‌لیست شفاف شرط‌ها
class DecisionCard extends StatelessWidget {
  const DecisionCard({super.key, required this.decision});
  final Decision decision;

  static const _green = Color(0xFF2E9E5B);
  static const _amber = Color(0xFFE0A100);
  static const _red = Color(0xFFD64545);

  @override
  Widget build(BuildContext context) {
    final d = decision;
    final color = switch (d.verdict) {
      Verdict.enter => _green,
      Verdict.wait => _amber,
      Verdict.avoid => _red,
    };
    final icon = switch (d.verdict) {
      Verdict.enter => Icons.check_circle,
      Verdict.wait => Icons.hourglass_top,
      Verdict.avoid => Icons.block,
    };
    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.title,
                    style: TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 2),
                Text(d.subtitle, style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ]),
          if (d.strength.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('قدرت شواهد آماری: ${d.strength}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
          const Divider(height: 20),
          for (final c in d.checks) _row(c),
        ]),
      ),
    );
  }

  Widget _row(CheckItem c) {
    final IconData icon;
    final Color color;
    if (c.ok == true) {
      icon = Icons.check_circle;
      color = _green;
    } else if (c.ok == false) {
      icon = Icons.cancel;
      color = _red;
    } else {
      icon = Icons.info_outline;
      color = Colors.grey;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(c.label, style: const TextStyle(fontSize: 13))),
        const SizedBox(width: 8),
        Text(c.detail, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}
