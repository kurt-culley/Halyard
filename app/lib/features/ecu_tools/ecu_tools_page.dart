import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'ecu_tools_controller.dart';
import 'strings.dart';

@RoutePage()
class EcuToolsPage extends StatelessWidget {
  const EcuToolsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => EcuToolsController(c.read<Session>(), c.read<SwitchablePolicy>()),
    child: const _EcuToolsView(),
  );
}

class _EcuToolsView extends StatelessWidget {
  const _EcuToolsView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EcuToolsController>();
    final theme = Theme.of(context);
    if (!c.isOnline) return const Center(child: Text(EcuToolsStrings.notOnline));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (!c.canChange) Text(EcuToolsStrings.readOnly, style: TextStyle(color: theme.colorScheme.error)),
        if (c.message != null) Text(c.message!),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(width: 420, child: _Clock(c)),
            SizedBox(width: 420, child: _Password(c)),
            SizedBox(width: 420, child: _Reset(c)),
          ],
        ),
      ],
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

class _Clock extends StatefulWidget {
  const _Clock(this.c);
  final EcuToolsController c;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  DateTime _new = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final theme = Theme.of(context);
    final t = c.ecuTime;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(EcuToolsStrings.dateTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(EcuToolsStrings.ecuTime),
            Text(
              t == null
                  ? EcuToolsStrings.noClock
                  : '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}  ${_two(t.day)}/${_two(t.month)}/${t.year}',
              style: t == null ? theme.textTheme.bodyMedium : theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(EcuToolsStrings.newTime),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text('${_two(_new.day)}/${_two(_new.month)}/${_new.year}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _new,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2099),
                    );
                    if (d != null) setState(() => _new = DateTime(d.year, d.month, d.day, _new.hour, _new.minute));
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text('${_two(_new.hour)}:${_two(_new.minute)}'),
                  onPressed: () async {
                    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_new));
                    if (tm != null) {
                      setState(() => _new = DateTime(_new.year, _new.month, _new.day, tm.hour, tm.minute));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: c.canChange ? () => c.setTime(_new) : null,
              child: const Text(EcuToolsStrings.saveTime),
            ),
          ],
        ),
      ),
    );
  }
}

class _Password extends StatefulWidget {
  const _Password(this.c);
  final EcuToolsController c;

  @override
  State<_Password> createState() => _PasswordState();
}

class _PasswordState extends State<_Password> {
  final _a = TextEditingController(), _b = TextEditingController();
  late final _contact = TextEditingController(text: widget.c.contact);
  bool _permanent = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _problem(String text, {bool clear = false}) async {
    if (clear) {
      _a.clear();
      _b.clear();
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(text),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text(EcuToolsStrings.ok))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final theme = Theme.of(context);
    final v = c.view;
    final edit = c.canChange;
    if (!_contact.text.contains(c.contact) && v.contact) _contact.text = c.contact;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(EcuToolsStrings.pwTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(EcuToolsStrings.pwState),
            Text(v.state, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _contact,
              enabled: v.contact && edit,
              maxLength: 96,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(labelText: EcuToolsStrings.contact, border: OutlineInputBorder()),
            ),
            TextField(
              controller: _a,
              enabled: edit,
              obscureText: true,
              maxLength: 32,
              decoration: const InputDecoration(labelText: EcuToolsStrings.password),
            ),
            TextField(
              controller: _b,
              enabled: edit,
              obscureText: true,
              maxLength: 32,
              decoration: const InputDecoration(labelText: EcuToolsStrings.again),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(EcuToolsStrings.permanent),
              value: _permanent,
              onChanged: v.permanent && edit ? (x) => setState(() => _permanent = x ?? false) : null,
            ),
            Row(
              children: [
                FilledButton(
                  onPressed: v.lock && edit
                      ? () async {
                          final p = c.lockCheck(_a.text, _b.text);
                          if (p != null) return _problem(p, clear: p == EcuToolsStrings.mismatch);
                          await c.lock(_a.text, _contact.text);
                        }
                      : null,
                  child: const Text(EcuToolsStrings.lock),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: v.unlock && edit
                      ? () async {
                          final p = c.unlockCheck(_a.text, _b.text);
                          if (p != null) return _problem(p, clear: true);
                          await c.unlock(_a.text, permanent: _permanent);
                        }
                      : null,
                  child: const Text(EcuToolsStrings.unlock),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Reset extends StatelessWidget {
  const _Reset(this.c);
  final EcuToolsController c;

  Future<void> _run(BuildContext context) async {
    final field = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(EcuToolsStrings.resetTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(EcuToolsStrings.resetPrompt),
              const SizedBox(height: 8),
              Text(EcuToolsStrings.resetWarning, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              Text(EcuToolsStrings.resetFirmware, style: Theme.of(context).textTheme.bodySmall),
              TextField(controller: field, autofocus: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(EcuToolsStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(EcuToolsStrings.ok)),
        ],
      ),
    );
    final typed = field.text;
    field.dispose();
    if (!(go ?? false) || !context.mounted) return;
    // The original accepted any text containing "erase", in any case.
    if (!typed.toLowerCase().contains('erase')) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: const Text(EcuToolsStrings.wrongText),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text(EcuToolsStrings.ok))],
        ),
      );
      return;
    }
    final ok = await c.factoryReset();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(EcuToolsStrings.resetTitle),
        content: Text(ok ? EcuToolsStrings.resetDone : EcuToolsStrings.resetFailed),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text(EcuToolsStrings.ok))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(EcuToolsStrings.resetTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(EcuToolsStrings.resetWarning),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: c.canChange ? () => _run(context) : null,
              child: const Text(EcuToolsStrings.resetButton),
            ),
          ],
        ),
      ),
    );
  }
}
