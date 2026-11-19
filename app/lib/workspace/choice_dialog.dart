import 'package:material_ui/material_ui.dart';

import 'strings.dart';

/// A searchable list of choices; returns the chosen one, or null. Also the command palette's body.
Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<(String label, T value)> choices,
}) => showDialog<T>(
  context: context,
  builder: (context) => _ChoiceDialog<T>(title: title, choices: choices),
);

class _ChoiceDialog<T> extends StatefulWidget {
  const _ChoiceDialog({required this.title, required this.choices});
  final String title;
  final List<(String, T)> choices;

  @override
  State<_ChoiceDialog<T>> createState() => _ChoiceDialogState<T>();
}

class _ChoiceDialogState<T> extends State<_ChoiceDialog<T>> {
  var _query = '';

  /// Every word of the query appears in the label, in any order and case.
  List<(String, T)> get _matches {
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return [
      for (final c in widget.choices)
        if (words.every(c.$1.toLowerCase().contains)) c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 360,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: WorkspaceStrings.search, prefixIcon: Icon(Icons.search)),
              onChanged: (q) => setState(() => _query = q),
              onSubmitted: (q) {
                _query = q;
                final m = _matches;
                if (m.isNotEmpty) Navigator.of(context).pop(m.first.$2);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text(WorkspaceStrings.noMatches))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(matches[i].$1),
                        onTap: () => Navigator.of(context).pop(matches[i].$2),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
