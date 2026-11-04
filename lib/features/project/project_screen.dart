import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import '../terminal/terminals_screen.dart';
import 'changes_tab.dart';
import 'editor_tab.dart';
import 'files_tab.dart';
import 'git_tab.dart';
import 'open_file.dart';
import 'project_api.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';

/// Tab ids accepted by [ProjectScreen.initialTab], in display order.
const projectTabs = ['changes', 'files', 'editor', 'git', 'terminal'];

/// The desktop's context panel for one project: Changes, Files, Editor, Git
/// and Terminal.
class ProjectScreen extends ConsumerStatefulWidget {
  const ProjectScreen({
    super.key,
    required this.desktopId,
    required this.workspaceId,
    required this.workspaceName,
    this.initialTab,
  });
  final String desktopId;
  final String workspaceId;
  final String workspaceName;

  /// changes | files | editor | git | terminal
  final String? initialTab;

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: projectTabs.length,
    vsync: this,
    initialIndex: projectTabs.indexOf(widget.initialTab ?? 'changes').clamp(0, projectTabs.length - 1),
  );

  ProjectKey get _key => (desktopId: widget.desktopId, workspaceId: widget.workspaceId);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() => confirmDialog(
        context,
        title: 'Discard unsaved changes?',
        body: 'The file in the editor has edits that are not saved on the desktop.',
        confirm: 'Discard',
        destructive: true,
      );

  /// Opens [path] in the Editor tab, asking first when edits would be lost.
  Future<void> _open(String path) async {
    final s = ref.read(openFileProvider(_key));
    if (s.path != path && s.dirty && !await _confirmDiscard()) return;
    if (!mounted) return;
    if (s.path != path || s.error != null) {
      ref.read(openFileProvider(_key).notifier).open(path);
    }
    _tabs.animateTo(projectTabs.indexOf('editor'));
  }

  @override
  Widget build(BuildContext context) {
    final dirty = ref.watch(openFileProvider(_key).select((s) => s.dirty));
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          ref.read(openFileProvider(_key).notifier).setDirty(false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.workspaceName, overflow: TextOverflow.ellipsis),
          actions: const [HelpButton(topic: HelpTopic.project)],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Changes'),
              const Tab(text: 'Files'),
              Tab(text: dirty ? 'Editor •' : 'Editor'),
              const Tab(text: 'Git'),
              const Tab(text: 'Terminal'),
            ],
          ),
        ),
        body: Column(children: [
          const ConnectionStrip(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              // Horizontal swipes belong to the diff, editor and terminal.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _KeepAlive(child: ChangesTab(projectKey: _key)),
                _KeepAlive(child: FilesTab(projectKey: _key, onOpen: _open)),
                _KeepAlive(
                  child: EditorTab(
                    projectKey: _key,
                    onBrowse: () => _tabs.animateTo(projectTabs.indexOf('files')),
                  ),
                ),
                _KeepAlive(child: GitTab(projectKey: _key)),
                _KeepAlive(
                  child: TerminalsView(desktopId: widget.desktopId, workspaceId: widget.workspaceId),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
