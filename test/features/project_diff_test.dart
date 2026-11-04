import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/features/project/diff.dart';

const modified = '''diff --git a/src/app.ts b/src/app.ts
index 1111111..2222222 100644
--- a/src/app.ts
+++ b/src/app.ts
@@ -1,4 +1,5 @@
 import x from "x";
-const a = 1;
+const a = 2;
+const b = 3;
 
 export default a;
@@ -10,2 +11,1 @@ function f() {
-  -- not a header
-  old();
+  newer();
''';

const added = '''diff --git a/notes.md b/notes.md
new file mode 100644
index 0000000..3333333
--- /dev/null
+++ b/notes.md
@@ -0,0 +1,2 @@
+# Notes
+hello
\\ No newline at end of file
''';

const deleted = '''diff --git a/old.txt b/old.txt
deleted file mode 100644
index 4444444..0000000
--- a/old.txt
+++ /dev/null
@@ -1 +0,0 @@
-bye
''';

const binary = '''diff --git a/logo.png b/logo.png
index 5555555..6666666 100644
Binary files a/logo.png and b/logo.png differ
''';

const renamed = '''diff --git a/a.txt b/b.txt
similarity index 100%
rename from a.txt
rename to b.txt
''';

void main() {
  test('parses files, hunks, counts and line numbers', () {
    final files = parseUnifiedDiff(modified + added + deleted + binary + renamed);
    expect(files.map((f) => f.path), ['src/app.ts', 'notes.md', 'old.txt', 'logo.png', 'b.txt']);

    final m = files[0];
    expect(m.hunks.length, 2);
    expect(m.additions, 3);
    expect(m.deletions, 3);
    expect(m.isNew || m.isDeleted, isFalse);
    final first = m.hunks[0].lines;
    expect(first.map((l) => l.kind), [
      DiffLineKind.context,
      DiffLineKind.remove,
      DiffLineKind.add,
      DiffLineKind.add,
      DiffLineKind.context,
      DiffLineKind.context,
    ]);
    expect(first[1].oldNo, 2);
    expect(first[2].newNo, 2);
    expect(first[3].newNo, 3);
    expect(first[4].text, '');
    // A removed line starting with "--" stays inside the hunk.
    expect(m.hunks[1].lines.first.kind, DiffLineKind.remove);
    expect(m.hunks[1].lines.first.text, '  -- not a header');

    final a = files[1];
    expect(a.isNew, isTrue);
    expect(a.additions, 2);
    expect(a.hunks.single.lines.last.kind, DiffLineKind.meta);

    final d = files[2];
    expect(d.isDeleted, isTrue);
    expect(d.path, 'old.txt');
    expect(d.deletions, 1);

    expect(files[3].isBinary, isTrue);
    expect(files[3].hunks, isEmpty);

    expect(files[4].isRename, isTrue);
    expect(files[4].oldPath, 'a.txt');
  });

  test('plain unified diffs without git headers and empty input', () {
    expect(parseUnifiedDiff(''), isEmpty);
    final files = parseUnifiedDiff('--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n--- a/y\n+++ b/y\n@@ -1 +1 @@\n-c\n+d\n');
    expect(files.map((f) => f.path), ['x', 'y']);
    expect(files.every((f) => f.additions == 1 && f.deletions == 1), isTrue);
  });

  test('a diff cut off mid-hunk keeps what arrived', () {
    final files = parseUnifiedDiff('diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,10 +1,10 @@\n-a\n+b');
    expect(files.single.additions, 1);
    expect(files.single.deletions, 1);
  });
}
