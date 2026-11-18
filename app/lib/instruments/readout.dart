import 'package:material_ui/material_ui.dart';

/// A digital readout: a value under its label. Dimmed when stale; in the error colour when out of range.
class Readout extends StatelessWidget {
  const Readout({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.stale = false,
    this.alarm = false,
  });

  final String label;
  final String value;
  final String? unit;
  final bool stale;
  final bool alarm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = alarm ? theme.colorScheme.error : null;
    return Card(
      child: Opacity(
        opacity: stale ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: theme.textTheme.headlineSmall?.copyWith(color: colour),
                    ),
                    if (unit != null && unit!.isNotEmpty) TextSpan(text: ' $unit', style: theme.textTheme.bodySmall),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
