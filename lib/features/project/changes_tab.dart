import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'project_api.dart';
import 'project_widgets.dart';

/// Panel for git errors: a non-repo (`bad_request`) reads as an empty state.
Widget gitErrorPanel(BuildContext context, Object e, VoidCallback onRetry) {
  if (e is RpcError && e.code == 'bad_request') {
    return ListView(children: [
      const SizedBox(height: 100),
      EmptyPanel(
        title: 'Not a git repository',
        body: e.message.isNotEmpty ? e.message : 'This project folder is not a git repo.',
      ),
    ]);
  }
  return ErrorPanel(message: e is RpcError ? e.readable : '$e', onRetry: onRetry);
}

/// Everything changed against HEAD (`git.diff_head`), like the desktop's
/// Changes panel.
class ChangesTab extends ConsumerWidget {
  const ChangesTab({super.key, required this.projectKey});
  final ProjectKey projectKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(diffHeadProvider(projectKey));
    Future<void> refresh() => ref.refresh(diffHeadProvider(projectKey).future);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => RefreshIndicator(onRefresh: refresh, child: gitErrorPanel(context, e, refresh)),
      data: (files) {
        final adds = files.fold<int>(0, (a, f) => a + f.additions);
        final dels = files.fold<int>(0, (a, f) => a + f.deletions);
        return RefreshIndicator(
          onRefresh: refresh,
          child: files.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 100),
                  EmptyPanel(title: 'No changes', body: 'The working tree matches HEAD.'),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Row(children: [
                      Eyebrow('${files.length} file${files.length == 1 ? '' : 's'} changed'),
                      const Spacer(),
                      DiffCounts(additions: adds, deletions: dels),
                    ]),
                    const SizedBox(height: 8),
                    for (final f in files) ...[
                      DiffFileTile(
                        file: f,
                        onTap: () => DiffScreen.push(context,
                            title: f.path,
                            load: () async => [f]),
                      ),
                      const SizedBox(height: 6),
                    ],
                    const SizedBox(height: 8),
                    Text('Pull to refresh.',
                        textAlign: TextAlign.center,
                        style: mono(context, size: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
        );
      },
    );
  }
}
