import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../desktops/capabilities.dart';
import 'languages.dart';
import 'open_file.dart';
import 'project_api.dart';
import 'project_widgets.dart';

/// `fs.read` in a highlighted code editor; `fs.write` on save when the
/// desktop allows edits.
class EditorTab extends ConsumerStatefulWidget {
  const EditorTab({super.key, required this.projectKey, this.onBrowse});
  final ProjectKey projectKey;

  /// Switches to the Files tab.
  final VoidCallback? onBrowse;

  @override
  ConsumerState<EditorTab> createState() => _EditorTabState();
}

class _EditorTabState extends ConsumerState<EditorTab> {
  CodeLineEditingController? _controller;
  int _version = -1;
  Object? _loadedLines;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _sync(OpenFileState s) {
    if (s.version == _version) return;
    _version = s.version;
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    if (s.path == null || s.loading || s.error != null) {
      _controller = null;
      return;
    }
    final c = CodeLineEditingController.fromText(s.content);
    _loadedLines = c.codeLines;
    c.addListener(_onChanged);
    _controller = c;
  }

  void _onChanged() {
    final c = _controller;
    if (c == null) return;
    // The listener also fires for selection moves; only text edits replace
    // the line list.
    if (!identical(c.codeLines, _loadedLines)) {
      ref.read(openFileProvider(widget.projectKey).notifier).setDirty(true);
    }
  }

  Future<void> _save() async {
    final c = _controller;
    if (c == null) return;
    final caps = ref.read(capabilitiesProvider(widget.projectKey.desktopId));
    if (!caps.edit) {
      showSnack(context, 'Editing is off. $allowOnDesktopHint.');
      return;
    }
    final err = await ref.read(openFileProvider(widget.projectKey).notifier).save(c.text);
    if (!mounted) return;
    if (err != null) {
      showSnack(context, err);
    } else {
      _loadedLines = c.codeLines;
      invalidateGit(ref, widget.projectKey);
      showSnack(context, 'Saved.');
    }
  }

  Future<void> _reload() async {
    final s = ref.read(openFileProvider(widget.projectKey));
    if (s.dirty &&
        !await confirmDialog(context,
            title: 'Discard changes?',
            body: 'Reloading replaces your unsaved edits with the file on the desktop.',
            confirm: 'Discard',
            destructive: true)) {
      return;
    }
    await ref.read(openFileProvider(widget.projectKey).notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = ref.watch(openFileProvider(widget.projectKey));
    final caps = ref.watch(capabilitiesProvider(widget.projectKey.desktopId));
    _sync(s);

    if (s.path == null) {
      return EmptyPanel(
        title: 'No file open',
        body: 'Pick a file in the Files tab.',
        action: widget.onBrowse == null
            ? null
            : OutlinedButton(onPressed: widget.onBrowse, child: const Text('Browse files')),
      );
    }

    final header = Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
      child: Row(children: [
        if (s.dirty)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(Icons.circle, size: 8, color: cs.primary),
          ),
        Expanded(
          child: Text(s.path!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(context, size: 12, color: cs.onSurface)),
        ),
        IconButton(
          tooltip: 'Reload',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: s.loading ? null : _reload,
        ),
        if (caps.edit)
          IconButton(
            tooltip: 'Save',
            visualDensity: VisualDensity.compact,
            icon: s.saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.save_outlined, size: 20, color: s.dirty ? cs.primary : null),
            onPressed: s.dirty && !s.saving && _controller != null ? _save : null,
          ),
      ]),
    );

    Widget body;
    if (s.loading) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (s.error != null) {
      body = ErrorPanel(message: s.error!, onRetry: _reload);
    } else {
      final lang = languageIdFor(s.path!);
      final mode = lang == null ? null : languageMode(lang);
      final base = dark ? atomOneDarkTheme : atomOneLightTheme;
      final theme = {
        ...base,
        'root': TextStyle(color: cs.onSurface, backgroundColor: Colors.transparent),
      };
      body = CodeEditor(
        key: ValueKey(s.version),
        controller: _controller,
        readOnly: !caps.edit,
        wordWrap: false,
        style: CodeEditorStyle(
          fontSize: 12.5,
          fontFamily: monoFamily,
          textColor: cs.onSurface,
          backgroundColor: dark ? Neutral.n950 : Colors.white,
          cursorColor: cs.primary,
          selectionColor: cs.primary.withValues(alpha: 0.3),
          cursorLineColor: cs.onSurface.withValues(alpha: 0.04),
          codeTheme: mode == null
              ? null
              : CodeHighlightTheme(
                  languages: {lang!: CodeHighlightThemeMode(mode: mode)},
                  theme: theme,
                ),
        ),
        indicatorBuilder: (context, editing, chunk, notifier) => Row(children: [
          DefaultCodeLineNumber(
            controller: editing,
            notifier: notifier,
            textStyle: mono(context, size: 11, color: cs.onSurfaceVariant),
            focusedTextStyle: mono(context, size: 11, color: cs.onSurface),
          ),
          const SizedBox(width: 6),
        ]),
      );
    }

    return Column(children: [
      if (!caps.edit) const EditHint(),
      header,
      Expanded(child: body),
    ]);
  }
}
