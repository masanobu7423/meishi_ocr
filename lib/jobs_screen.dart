import 'package:flutter/material.dart';

import 'theme.dart';

/// 職種の一覧: the user's own list of trades for the form's dropdown.
/// Add at the top, rename or delete per row. Edits go straight into [jobs]
/// (a mutable copy the shell owns and saves once when this screen closes:
/// one write, no racing saves). Renaming does not touch cards already saved
/// with the old name (ponytail: they still show in the dropdown as a value
/// in use). Deleting every entry brings the default list back.
class JobsScreen extends StatefulWidget {
  final List<String> jobs;
  const JobsScreen({super.key, required this.jobs});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<String> get _jobs => widget.jobs;
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  void _commit() => setState(() {});

  void _append() {
    final v = _add.text.trim();
    if (v.isEmpty || _jobs.contains(v)) return;
    _jobs.add(v);
    _add.clear();
    _commit();
  }

  Future<void> _rename(int i) async {
    final v = await showDialog<String>(context: context, builder: (_) => _RenameDialog(_jobs[i]));
    if (v == null || v.isEmpty || v == _jobs[i] || _jobs.contains(v)) return;
    _jobs[i] = v;
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('職種の一覧')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.gutter, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _add,
                    decoration: const InputDecoration(labelText: '職種を追加（例: 鳶、左官）'),
                    onSubmitted: (_) => _append(),
                  ),
                ),
                const SizedBox(width: AppSpace.unit),
                FilledButton.tonalIcon(onPressed: _append, icon: const Icon(Icons.add), label: const Text('追加')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.gutter, 0),
            child: Text('確認画面の「職種」の選択肢です。名前を変えても保存済みの名刺はそのままです。すべて消すと既定の一覧に戻ります',
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _jobs.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(_jobs[i]),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        tooltip: '名前を変える', icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(i)),
                    IconButton(
                      tooltip: '削除',
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      onPressed: () {
                        _jobs.removeAt(i);
                        _commit();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Owns its controller so it outlives the dialog's closing animation.
class _RenameDialog extends StatefulWidget {
  final String current;
  const _RenameDialog(this.current);

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _c = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('職種の名前を変える'),
        content: TextField(controller: _c, autofocus: true, decoration: const InputDecoration(labelText: '職種')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, _c.text.trim()), child: const Text('変更')),
        ],
      );
}
