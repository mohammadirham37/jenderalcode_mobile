/// Unified diff parsing for the Changes panel and diff viewer.
library;

enum DiffLineKind { context, add, remove, meta }

class DiffLine {
  const DiffLine(this.kind, this.text, {this.oldNo, this.newNo});
  final DiffLineKind kind;

  /// The line without its leading `+`/`-`/space marker.
  final String text;
  final int? oldNo;
  final int? newNo;
}

class DiffHunk {
  DiffHunk(this.header, this.oldStart, this.newStart);
  final String header;
  final int oldStart;
  final int newStart;
  final lines = <DiffLine>[];
}

class DiffFile {
  DiffFile({this.oldPath = '', this.newPath = ''});
  String oldPath;
  String newPath;
  bool isNew = false;
  bool isDeleted = false;
  bool isBinary = false;
  bool isRename = false;
  int additions = 0;
  int deletions = 0;
  final hunks = <DiffHunk>[];

  /// The path to show: the old one for deletions, else the new one.
  String get path => isDeleted ? oldPath : (newPath.isNotEmpty ? newPath : oldPath);
}

final _hunkRe = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

String _stripPrefix(String p) {
  final t = p.split('\t').first.trim();
  if (t.startsWith('a/') || t.startsWith('b/')) return t.substring(2);
  return t;
}

/// Parses `git diff` output. Tolerates diffs without `diff --git` headers and
/// diffs the desktop cut off at its size limit.
List<DiffFile> parseUnifiedDiff(String text) {
  final files = <DiffFile>[];
  DiffFile? cur;
  DiffHunk? hunk;
  var oldLeft = 0, newLeft = 0, oldNo = 0, newNo = 0;
  var sawMinus = false;

  DiffFile start() {
    final f = DiffFile();
    files.add(f);
    hunk = null;
    sawMinus = false;
    oldLeft = newLeft = 0;
    return f;
  }

  for (final raw in text.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    final h = hunk;
    if (h != null && (oldLeft > 0 || newLeft > 0)) {
      if (line.startsWith('+')) {
        h.lines.add(DiffLine(DiffLineKind.add, line.substring(1), newNo: newNo++));
        newLeft--;
        cur!.additions++;
        continue;
      }
      if (line.startsWith('-')) {
        h.lines.add(DiffLine(DiffLineKind.remove, line.substring(1), oldNo: oldNo++));
        oldLeft--;
        cur!.deletions++;
        continue;
      }
      if (line.startsWith(' ') || line.isEmpty) {
        h.lines.add(DiffLine(DiffLineKind.context, line.isEmpty ? '' : line.substring(1),
            oldNo: oldNo++, newNo: newNo++));
        oldLeft--;
        newLeft--;
        continue;
      }
      if (line.startsWith('\\')) {
        h.lines.add(DiffLine(DiffLineKind.meta, line));
        continue;
      }
      // Anything else ends the hunk early (truncated or malformed counts).
      oldLeft = newLeft = 0;
    } else if (h != null && line.startsWith('\\')) {
      h.lines.add(DiffLine(DiffLineKind.meta, line));
      continue;
    }

    if (line.startsWith('diff --git ')) {
      cur = start();
      final rest = line.substring('diff --git '.length);
      final i = rest.lastIndexOf(' b/');
      if (i >= 0) {
        cur.oldPath = _stripPrefix(rest.substring(0, i));
        cur.newPath = _stripPrefix(rest.substring(i + 1));
      }
      continue;
    }
    if (line.startsWith('--- ')) {
      // A plain unified diff starts a new file at `---`.
      if (cur == null || hunk != null || sawMinus) cur = start();
      sawMinus = true;
      final p = line.substring(4).split('\t').first.trim();
      if (p == '/dev/null') {
        cur.isNew = true;
      } else {
        cur.oldPath = _stripPrefix(p);
      }
      continue;
    }
    if (line.startsWith('+++ ') && cur != null && hunk == null) {
      final p = line.substring(4).split('\t').first.trim();
      if (p == '/dev/null') {
        cur.isDeleted = true;
      } else {
        cur.newPath = _stripPrefix(p);
      }
      continue;
    }
    final m = _hunkRe.firstMatch(line);
    if (m != null) {
      cur ??= start();
      oldNo = int.parse(m.group(1)!);
      newNo = int.parse(m.group(3)!);
      oldLeft = m.group(2) == null ? 1 : int.parse(m.group(2)!);
      newLeft = m.group(4) == null ? 1 : int.parse(m.group(4)!);
      final nh = DiffHunk(line, oldNo, newNo);
      cur.hunks.add(nh);
      hunk = nh;
      continue;
    }
    if (cur == null) continue;
    if (line.startsWith('new file mode')) {
      cur.isNew = true;
    } else if (line.startsWith('deleted file mode')) {
      cur.isDeleted = true;
    } else if (line.startsWith('rename from ')) {
      cur.isRename = true;
      cur.oldPath = line.substring('rename from '.length);
    } else if (line.startsWith('rename to ')) {
      cur.isRename = true;
      cur.newPath = line.substring('rename to '.length);
    } else if (line.startsWith('Binary files ') || line.startsWith('GIT binary patch')) {
      cur.isBinary = true;
    }
  }
  return files;
}
