import '../../core/rpc/models.dart';

/// Result of `git.status`.
class GitStatus {
  const GitStatus({this.branch, required this.files});

  /// null on a detached HEAD.
  final String? branch;
  final List<FileStatus> files;

  factory GitStatus.fromJson(Json j) => GitStatus(
        branch: j['branch'] is String ? j['branch'] as String : null,
        files: FileStatus.listFrom(j['files']),
      );

  GitGroups get groups => GitGroups.from(files);
}

/// Files split like the desktop's Git panel. A file with both staged and
/// unstaged changes is in both lists.
class GitGroups {
  const GitGroups({required this.staged, required this.unstaged});
  final List<FileStatus> staged;
  final List<FileStatus> unstaged;

  factory GitGroups.from(List<FileStatus> files) => GitGroups(
        staged: [for (final f in files) if (f.isStaged) f],
        unstaged: [for (final f in files) if (f.isUnstaged) f],
      );

  bool get isClean => staged.isEmpty && unstaged.isEmpty;
}

/// The status letter shown for a row in the staged or unstaged list.
StatusKind displayKind(FileStatus f, {required bool staged}) =>
    staged ? f.index : f.worktree;
