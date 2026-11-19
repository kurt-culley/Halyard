import 'package:material_ui/material_ui.dart';

import 'sparkline.dart';

/// A digital readout: a value under its label. Dimmed when stale; in the error colour when out of range. With
/// [history] it draws the recent values under the value, and with [fraction] where the value sits in its range.
class Readout extends StatelessWidget {
  const Readout({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.stale = false,
    this.alarm = false,
    this.history,
    this.fraction,
    this.action,
  });

  final String label;
  final String value;
  final String? unit;
  final bool stale;
  final bool alarm;
  final List<double>? history;

  /// 0 to 1 across the link's range; NaN or null draws no bar.
  final double? fraction;

  /// A small control in the corner, such as a pin.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colour = alarm ? scheme.error : null;
    final f = fraction;
    return Card(
      child: Opacity(
        opacity: stale ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
                  ),
                  ?action,
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colour,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (unit != null && unit!.isNotEmpty) TextSpan(text: ' $unit', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (history != null) ...[
                const SizedBox(height: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Sparkline(values: history!, colour: colour),
                  ),
                ),
              ],
              if (f != null && f.isFinite) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: f.clamp(0.0, 1.0),
                      minHeight: 4,
                      color: colour,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
