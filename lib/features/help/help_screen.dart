import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'help_content.dart';

/// Opens the guide at [topic].
void openHelp(BuildContext context, [HelpTopic topic = HelpTopic.start]) =>
    context.push('/help?topic=${topic.name}');

/// "?" button for app bars: opens the guide at the screen's topic.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, this.topic = HelpTopic.start});
  final HelpTopic topic;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Help',
        icon: const Icon(Icons.help_outline),
        onPressed: () => openHelp(context, topic),
      );
}

/// The in-app guide: one expandable card per topic, the requested one open.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, this.initial});
  final HelpTopic? initial;

  static HelpTopic? parse(String? name) =>
      HelpTopic.values.where((t) => t.name == name).firstOrNull;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _keys = {for (final s in helpSections) s.topic: GlobalKey()};

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    if (t != null && t != helpSections.first.topic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[t]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final open = widget.initial ?? HelpTopic.start;
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Cara menggunakan JenderalCode Mobile',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 6),
          Text('Ketuk topik untuk melihat langkah-langkahnya.',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 16),
          for (final s in helpSections) ...[
            _SectionCard(key: _keys[s.topic], section: s, initiallyExpanded: s.topic == open),
            const SizedBox(height: 10),
          ],
        ]),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({super.key, required this.section, required this.initiallyExpanded});
  final HelpSection section;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = section;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // No divider lines around the expanded tile.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Icon(s.icon, size: 20, color: cs.primary),
          ),
          title: Text(s.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(s.summary,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.35)),
          ),
          children: [
            for (final (i, step) in s.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onPrimary)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step, style: const TextStyle(height: 1.45))),
                ]),
              ),
            if (s.tips.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Eyebrow('Tips'),
                  for (final tip in s.tips)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.lightbulb_outline, size: 15, color: cs.primary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(tip,
                              style: TextStyle(
                                  fontSize: 13, height: 1.45, color: cs.onSurfaceVariant)),
                        ),
                      ]),
                    ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
