import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'split_view.dart';
import 'strings.dart';
import 'workspace_controller.dart';

/// The user's pages: one tab per page, and the current page's tiles.
@RoutePage()
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({super.key});

  Future<void> _rename(BuildContext context, WorkspaceController c) async {
    final text = TextEditingController(text: c.page.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(WorkspaceStrings.rename),
        content: TextField(controller: text, autofocus: true, onSubmitted: (v) => Navigator.of(context).pop(v)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(WorkspaceStrings.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(text.text), child: const Text(WorkspaceStrings.ok)),
        ],
      ),
    );
    if (name != null) c.rename(name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<WorkspaceController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (i, p) in c.pages.indexed)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(p.name),
                            selected: i == c.current,
                            onSelected: (_) => c.select(i),
                          ),
                        ),
                      IconButton(tooltip: WorkspaceStrings.newPage, icon: const Icon(Icons.add), onPressed: c.addPage),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: WorkspaceStrings.undo,
                icon: const Icon(Icons.undo),
                onPressed: c.canUndo ? c.undo : null,
              ),
              IconButton(
                tooltip: WorkspaceStrings.redo,
                icon: const Icon(Icons.redo),
                onPressed: c.canRedo ? c.redo : null,
              ),
              PopupMenuButton<int>(
                onSelected: (v) => v == 0 ? _rename(context, c) : c.removePage(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0, child: Text(WorkspaceStrings.rename)),
                  PopupMenuItem(value: 1, child: Text(WorkspaceStrings.delete)),
                ],
              ),
            ],
          ),
        ),
        const Expanded(child: SplitView()),
      ],
    );
  }
}
