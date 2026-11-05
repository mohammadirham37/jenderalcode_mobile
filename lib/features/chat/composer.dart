import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/theme/app_theme.dart';
import 'chat_catalog.dart';
import 'composer_logic.dart';
import 'images.dart';

typedef SendFn = Future<bool> Function(
    String text, List<String> attachments, List<ImageAttachment> images);

/// "Enhance prompt" (`chat.enhance`): the draft rewritten by the session's
/// model. Throws [RpcError].
typedef EnhanceFn = Future<String> Function(String draft);

/// Message box with `@` file mentions (`fs.find`), the `/` skill menu
/// (`skills.list`) and photo attachments.
class Composer extends ConsumerStatefulWidget {
  const Composer({
    super.key,
    required this.desktopId,
    required this.workspaceId,
    required this.busy,
    required this.sending,
    required this.imagesAllowed,
    required this.onSend,
    required this.onStop,
    this.onEnhance,
    this.toolbar,
  });
  final String desktopId;
  final String? workspaceId;
  final bool busy;
  final bool sending;

  /// False when the selected model is known to lack vision.
  final bool imagesAllowed;
  final SendFn onSend;
  final VoidCallback onStop;

  /// Null when there is no session (or model) to enhance with.
  final EnhanceFn? onEnhance;

  /// Row above the text field (agent, model, context meter).
  final Widget? toolbar;

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  List<String> _attachments = const [];
  List<ImageAttachment> _images = const [];
  bool _preparing = false;
  bool _enhancing = false;

  MentionQuery? _mention;
  List<String> _found = const [];
  Timer? _findDebounce;
  int _findGen = 0;
  String? _slash;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onChanged);
  }

  @override
  void dispose() {
    _findDebounce?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final sel = _input.selection;
    final cursor = sel.isValid && sel.isCollapsed ? sel.baseOffset : -1;
    final text = _input.text;
    final m = widget.workspaceId == null ? null : activeMention(text, cursor);
    final slash = widget.workspaceId == null ? null : activeSlash(text, cursor);
    if (slash != _slash) setState(() => _slash = slash);
    if (m?.query != _mention?.query || (m == null) != (_mention == null)) {
      setState(() {
        _mention = m;
        if (m == null) _found = const [];
      });
      _findDebounce?.cancel();
      if (m != null) _findDebounce = Timer(const Duration(milliseconds: 150), () => _find(m.query));
    } else {
      _mention = m;
    }
  }

  Future<void> _find(String query) async {
    final hub = ref.read(hubProvider);
    final wid = widget.workspaceId;
    if (hub == null || wid == null || !hub.isKnown(widget.desktopId)) return;
    final gen = ++_findGen;
    try {
      final r = await hub.rpc(widget.desktopId).call('fs.find', {'workspace_id': wid, 'query': query});
      final paths = [for (final p in (r['paths'] as List? ?? const [])) if (p is String) p];
      if (mounted && gen == _findGen && _mention != null) setState(() => _found = paths);
    } on RpcError {
      if (mounted && gen == _findGen) setState(() => _found = const []);
    }
  }

  void _pickPath(String path) {
    final m = _mention;
    if (m == null) return;
    final r = applyMention(_input.text, m, path);
    final next = addAttachment(_attachments, path);
    if (identical(next, _attachments) && !_attachments.contains(path)) {
      _snack('Up to $maxAttachments files per message.');
    }
    setState(() {
      _attachments = next;
      _mention = null;
      _found = const [];
    });
    _input.value = TextEditingValue(text: r.text, selection: TextSelection.collapsed(offset: r.cursor));
  }

  void _pickSkill(String name) {
    final text = applySlash(_input.text, name);
    setState(() => _slash = null);
    _input.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: name.length + 2));
  }

  Future<void> _addImages(ImageSource source) async {
    final left = maxImages - _images.length;
    if (left <= 0) {
      _snack('Up to $maxImages images per message.');
      return;
    }
    final picker = ImagePicker();
    final List<XFile> files;
    try {
      if (source == ImageSource.camera) {
        final f = await picker.pickImage(
            source: ImageSource.camera,
            maxWidth: maxImageSide.toDouble(),
            maxHeight: maxImageSide.toDouble(),
            imageQuality: 90);
        files = f == null ? const [] : [f];
      } else {
        files = await picker.pickMultiImage(
            limit: left > 1 ? left : null,
            maxWidth: maxImageSide.toDouble(),
            maxHeight: maxImageSide.toDouble(),
            imageQuality: 90);
      }
    } on PlatformException catch (e) {
      _snack(e.code == 'camera_access_denied'
          ? 'Camera access is off for JenderalCode. Turn it on in the phone settings.'
          : 'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}.');
      return;
    }
    if (files.isEmpty || !mounted) return;
    setState(() => _preparing = true);
    try {
      var list = _images;
      for (final f in files.take(left)) {
        final img = await prepareImage(await f.readAsBytes());
        final err = imageAddError(list, img);
        if (err != null) {
          _snack(err);
          break;
        }
        list = [...list, img];
      }
      if (mounted) setState(() => _images = list);
    } catch (e) {
      _snack(e is ImagePrepError ? e.message : 'Could not read the image.');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _attachMenu() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (src != null) await _addImages(src);
  }

  Future<void> _send() async {
    final text = _input.text;
    final images = widget.imagesAllowed ? _images : const <ImageAttachment>[];
    if (text.trim().isEmpty && _attachments.isEmpty && images.isEmpty) return;
    // Only keep mentions still present in the text.
    final attachments = [for (final p in _attachments) if (text.contains('@$p')) p];
    final ok = await widget.onSend(text, attachments, images);
    if (ok && mounted && _input.text == text) {
      _input.clear();
      setState(() {
        _attachments = const [];
        _images = const [];
      });
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Replaces the draft with the enhanced prompt; the snackbar can undo it.
  Future<void> _enhance() async {
    final fn = widget.onEnhance;
    final draft = _input.text;
    if (fn == null || draft.trim().isEmpty || _enhancing) return;
    setState(() => _enhancing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final better = await fn(draft);
      if (!mounted) return;
      _input.value = TextEditingValue(
        text: better,
        selection: TextSelection.collapsed(offset: better.length),
      );
      messenger.showSnackBar(SnackBar(
        content: const Text('Prompt enhanced. Review it, then send.'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _input.value = TextEditingValue(
            text: draft,
            selection: TextSelection.collapsed(offset: draft.length),
          ),
        ),
      ));
    } on RpcError catch (e) {
      final old = e.code == 'bad_request' && e.message.contains('unknown method');
      messenger.showSnackBar(SnackBar(
        content: Text(old ? 'Update JenderalCode Desktop to v0.1.12 or newer to enhance prompts.' : e.readable),
      ));
    } finally {
      if (mounted) setState(() => _enhancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final busy = widget.busy;
    final wid = widget.workspaceId;
    final suggestions = _suggestions(context, wid);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ?suggestions,
          if (_attachments.isNotEmpty || _images.isNotEmpty || _preparing) _chips(context),
          ?widget.toolbar,
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            // One card: a full-width field, the actions below it.
            child: ListenableBuilder(
              listenable: Listenable.merge([_focus, _input]),
              builder: (context, _) {
                final hasText = _input.text.trim().isNotEmpty;
                final canEnhance = widget.onEnhance != null && hasText && !_enhancing;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(radius + 4),
                    border: Border.all(
                      color: _focus.hasFocus ? cs.primary : cs.outline,
                      width: _focus.hasFocus ? 1.5 : 1,
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                      controller: _input,
                      focusNode: _focus,
                      readOnly: _enhancing,
                      minLines: 2,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15.5, height: 1.4),
                      decoration: InputDecoration(
                        hintText: busy ? 'Steer the running turn…' : 'Message the agent… (@file, /skill)',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: false,
                        contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 6, 6),
                      child: Row(children: [
                        IconButton(
                          tooltip: widget.imagesAllowed ? 'Attach photo' : 'This model cannot read images',
                          onPressed: widget.imagesAllowed && !_preparing ? _attachMenu : null,
                          icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
                        ),
                        IconButton(
                          tooltip: 'Enhance prompt',
                          onPressed: canEnhance ? _enhance : null,
                          icon: _enhancing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.edit_note, size: 24),
                        ),
                        const Spacer(),
                        if (busy) ...[
                          IconButton.outlined(
                            tooltip: 'Stop',
                            onPressed: widget.onStop,
                            icon: Icon(Icons.stop, color: cs.error),
                          ),
                          const SizedBox(width: 6),
                        ],
                        IconButton.filled(
                          tooltip: busy ? 'Steer' : 'Send',
                          onPressed: widget.sending || _preparing ? null : _send,
                          icon: widget.sending
                              ? const SizedBox(
                                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.arrow_upward),
                        ),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget? _suggestions(BuildContext context, String? wid) {
    if (wid == null) return null;
    final cs = Theme.of(context).colorScheme;
    final List<(String, String?, VoidCallback)> rows;
    if (_slash != null) {
      final skills = ref.watch(skillsProvider((desktopId: widget.desktopId, workspaceId: wid)));
      final list = filterSkills(skills.value ?? const [], _slash!);
      rows = [
        for (final s in list.take(30))
          ('/${s.name}', s.description.isEmpty ? (s.project ? 'project' : null) : s.description,
              () => _pickSkill(s.name)),
      ];
      if (rows.isEmpty) return null;
    } else if (_mention != null && _found.isNotEmpty) {
      rows = [for (final p in _found) (p, null, () => _pickPath(p))];
    } else {
      return null;
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final (title, sub, onTap) in rows)
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(context, size: 12.5, color: cs.onSurface)),
                  if (sub != null)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chips(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
        children: [
          for (final p in _attachments)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.description_outlined, size: 14),
                label: Text(p.split('/').last, style: mono(context, size: 11.5)),
                onDeleted: () => setState(() => _attachments = [..._attachments]..remove(p)),
              ),
            ),
          for (final (i, img) in _images.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.image_outlined,
                    size: 14, color: widget.imagesAllowed ? null : cs.error),
                label: Text(
                    widget.imagesAllowed
                        ? '${img.width}×${img.height}'
                        : 'not sent: model has no vision',
                    style: mono(context, size: 11.5)),
                onDeleted: () => setState(() => _images = [..._images]..removeAt(i)),
              ),
            ),
          if (_preparing)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
    );
  }
}
