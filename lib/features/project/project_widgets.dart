import 'package:flutter/material.dart';

import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../desktops/capabilities.dart';
import 'diff.dart';

/// Shown above a panel whose writing actions are off.
class EditHint extends StatelessWidget {
  const EditHint({super.key, this.text = 'Read-only.'});
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$text $allowOnDesktopHint',
              style: mono(context, size: 11, color: cs.onSurfaceVariant)),
        ),
      ]),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Readable text for a write that failed or was refused locally.
String writeErrorText(RpcError e) =>
    e.code == 'not_allowed' ? 'Editing is off. $allowOnDesktopHint.' : e.readable;

/// Color for a git status letter.
Color statusColor(BuildContext context, StatusKind k) {
  final cs = Theme.of(context).colorScheme;
  return switch (k) {
    StatusKind.added || StatusKind.untracked => cs.primary,
    StatusKind.deleted => cs.error,
    StatusKind.modified || StatusKind.renamed || StatusKind.copied => const Color(0xFFD9A441),
    _ => cs.onSurfaceVariant,
  };
}

/// `+12 −3` in accent / error.
class DiffCounts extends StatelessWidget {
  const DiffCounts({super.key, required this.additions, required this.deletions});
  final int additions;
  final int deletions;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('+$additions', style: mono(context, size: 11.5, color: cs.primary)),
      const SizedBox(width: 6),
      Text('−$deletions', style: mono(context, size: 11.5, color: cs.error)),
    ]);
  }
}

/// One file row with its path and +/- counts.
class DiffFileTile extends StatelessWidget {
  const DiffFileTile({super.key, required this.file, required this.onTap});
  final DiffFile file;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tag = file.isNew
        ? 'new'
        : file.isDeleted
            ? 'deleted'
            : file.isRename
                ? 'renamed'
                : file.isBinary
                    ? 'binary'
                    : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(file.path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: mono(context, size: 12.5, color: cs.onSurface)),
                if (tag != null || file.isRename)
                  Text(file.isRename ? '$tag · from ${file.oldPath}' : tag!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(context, size: 10.5, color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 10),
            DiffCounts(additions: file.additions, deletions: file.deletions),
          ]),
        ),
      ),
    );
  }
}

class _Row {
  const _Row(this.kind, this.text, {this.oldNo, this.newNo, this.fileHeader = false});
  final DiffLineKind kind;
  final String text;
  final int? oldNo;
  final int? newNo;
  final bool fileHeader;
}

/// Colored unified diff for one or more files. Lines keep their width and
/// scroll horizontally.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.files});
  final List<DiffFile> files;

  static const _fontSize = 12.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <_Row>[];
    for (final f in files) {
      if (files.length > 1) rows.add(_Row(DiffLineKind.meta, f.path, fileHeader: true));
      if (f.isBinary) rows.add(const _Row(DiffLineKind.meta, 'Binary file'));
      for (final h in f.hunks) {
        rows.add(_Row(DiffLineKind.meta, h.header));
        for (final l in h.lines) {
          rows.add(_Row(l.kind, l.text, oldNo: l.oldNo, newNo: l.newNo));
        }
      }
    }
    if (rows.isEmpty) {
      return Center(
        child: Text('No changes to show.', style: mono(context, color: cs.onSurfaceVariant)),
      );
    }
    var maxLen = 0;
    for (final r in rows) {
      if (r.text.length > maxLen) maxLen = r.text.length;
    }
    final style = mono(context, size: _fontSize, color: cs.onSurface);
    final tp = TextPainter(
      text: TextSpan(text: 'mmmmmmmmmm', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final charW = tp.width / 10;
    tp.dispose();
    const gutter = 84.0;
    final addBg = cs.primary.withValues(alpha: 0.12);
    final delBg = cs.error.withValues(alpha: 0.12);

    return LayoutBuilder(builder: (context, c) {
      final width = (gutter + maxLen.clamp(0, 2000) * charW + 24).clamp(c.maxWidth, double.infinity);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              if (r.fileHeader) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
                  child: Text(r.text,
                      style: mono(context, size: 12, color: cs.onSurface, weight: FontWeight.w600)),
                );
              }
              final (bg, fg, mark) = switch (r.kind) {
                DiffLineKind.add => (addBg, cs.onSurface, '+'),
                DiffLineKind.remove => (delBg, cs.onSurface, '-'),
                DiffLineKind.meta => (cs.surfaceContainer, cs.onSurfaceVariant, ''),
                DiffLineKind.context => (Colors.transparent, cs.onSurface, ' '),
              };
              final markColor = switch (r.kind) {
                DiffLineKind.add => cs.primary,
                DiffLineKind.remove => cs.error,
                _ => cs.onSurfaceVariant,
              };
              String no(int? n) => n == null ? '' : '$n';
              return Container(
                color: bg,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 34,
                    child: Text(no(r.oldNo),
                        textAlign: TextAlign.right,
                        style: mono(context, size: 10.5, color: cs.onSurfaceVariant)),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(no(r.newNo),
                        textAlign: TextAlign.right,
                        style: mono(context, size: 10.5, color: cs.onSurfaceVariant)),
                  ),
                  SizedBox(
                    width: 14,
                    child: Text(mark,
                        textAlign: TextAlign.center,
                        style: mono(context, size: _fontSize, color: markColor)),
                  ),
                  Expanded(
                    child: Text(r.text,
                        softWrap: false,
                        style: mono(context, size: _fontSize, color: fg)),
                  ),
                ]),
              );
            },
          ),
        ),
      );
    });
  }
}

/// Full-screen diff, pushed from the Changes and Git tabs.
class DiffScreen extends StatefulWidget {
  const DiffScreen({super.key, required this.title, required this.load});
  final String title;
  final Future<List<DiffFile>> Function() load;

  static Future<void> push(BuildContext context,
          {required String title, required Future<List<DiffFile>> Function() load}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DiffScreen(title: title, load: load),
      ));

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  late Future<List<DiffFile>> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis, style: mono(context, size: 14)),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = widget.load()),
          ),
        ],
      ),
      body: FutureBuilder<List<DiffFile>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snap.hasError) {
            final e = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(e is RpcError ? e.readable : '$e',
                    textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
              ),
            );
          }
          return DiffView(files: snap.data ?? const []);
        },
      ),
    );
  }
}
