import '../../core/rpc/models.dart';

/// §6.6 limits for `chat.send`.
const maxAttachments = 20;
const maxImages = 4;

/// Total base64 payload for images. The sealed message must stay under the
/// relay's 1 MiB frame (sealing base64-encodes the JSON again, ×4/3), or the
/// relay drops this phone's connection.
const maxImagesTotalBytes = 680 * 1000;

/// An image ready for `chat.send` `images`: base64 without a `data:` prefix.
class ImageAttachment {
  const ImageAttachment({required this.mime, required this.data, this.width, this.height});
  final String mime;
  final String data;
  final int? width;
  final int? height;

  Json toJson() => {'mime': mime, 'data': data};
}

/// Images are refused only when the model is known to lack vision; unknown
/// (null) is allowed, like on the desktop.
bool imagesAllowedFor(Model? model) => model?.vision != false;

/// Why another image cannot be added, or null when it can.
String? imageAddError(List<ImageAttachment> current, ImageAttachment next) {
  if (current.length >= maxImages) return 'Up to $maxImages images per message.';
  final total = current.fold<int>(0, (n, i) => n + i.data.length) + next.data.length;
  if (total > maxImagesTotalBytes) {
    return 'Images are too large together for one message. Send fewer images, or one per message.';
  }
  return null;
}

/// Adds [path] once, up to [maxAttachments]. Returns the same list when full
/// or already present.
List<String> addAttachment(List<String> current, String path) {
  if (path.isEmpty || current.contains(path) || current.length >= maxAttachments) return current;
  return [...current, path];
}

/// An `@query` being typed at the cursor.
class MentionQuery {
  const MentionQuery(this.start, this.end, this.query);

  /// Index of the `@`.
  final int start;

  /// Cursor position (end of the query).
  final int end;
  final String query;
}

/// The `@word` that ends at [cursor], if any. The `@` must start the text or
/// follow whitespace, and the word has no whitespace.
MentionQuery? activeMention(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  var i = cursor - 1;
  while (i >= 0) {
    final c = text[i];
    if (c == '@') {
      if (i > 0 && !_isSpace(text[i - 1])) return null;
      return MentionQuery(i, cursor, text.substring(i + 1, cursor));
    }
    if (_isSpace(c)) return null;
    i--;
  }
  return null;
}

/// Replaces the mention with `@path ` and returns the new text and cursor.
({String text, int cursor}) applyMention(String text, MentionQuery m, String path) {
  final insert = '@$path ';
  final out = text.replaceRange(m.start, m.end, insert);
  return (text: out, cursor: m.start + insert.length);
}

/// The `/skill` prefix being typed: only when the message starts with `/`
/// and the cursor is still inside the first word.
String? activeSlash(String text, int cursor) {
  if (!text.startsWith('/') || cursor < 1 || cursor > text.length) return null;
  final head = text.substring(1, cursor);
  if (head.contains(RegExp(r'\s'))) return null;
  return head;
}

/// Replaces the first word with `/name `.
String applySlash(String text, String name) {
  final m = RegExp(r'^/\S*\s?').firstMatch(text);
  final rest = m == null ? text : text.substring(m.end);
  return '/$name $rest';
}

List<Skill> filterSkills(List<Skill> all, String query) {
  final q = query.toLowerCase();
  return [for (final s in all) if (s.name.toLowerCase().contains(q)) s];
}

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

/// `session.rename` accepts 1–200 characters.
String? validateTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return 'Enter a title.';
  if (t.length > 200) return 'Keep it under 200 characters.';
  return null;
}

/// Checkpoint restore needs the `edit` capability and something to restore.
bool canRestoreCheckpoints(Capabilities caps, int count) => caps.edit && count > 0;

/// Context fill as a fraction, or null when the window is unknown.
double? contextFraction(int lastInput, int? contextWindow) {
  if (contextWindow == null || contextWindow <= 0) return null;
  return (lastInput / contextWindow).clamp(0.0, 1.0);
}

String compactTokens(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
  return '$n';
}
