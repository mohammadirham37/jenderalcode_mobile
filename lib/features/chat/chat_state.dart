import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';

/// Everything the chat screen shows for one session. Immutable; events are
/// folded in with [applyEvent].
class ChatState {
  const ChatState({
    this.loading = true,
    this.loadError,
    this.session,
    this.messages = const [],
    this.toolRuns = const {},
    this.approvals = const {},
    this.status = 'idle',
    this.detail,
    this.busy = false,
    this.lastError,
    this.inputTokens,
    this.outputTokens,
    this.costEstimate,
    this.deciding = const {},
    this.sending = false,
  });

  final bool loading;
  final String? loadError;
  final Session? session;
  final List<Message> messages;

  /// Insertion-ordered by id.
  final Map<String, ToolRun> toolRuns;
  final Map<String, Approval> approvals;

  /// idle | thinking | streaming | running_tool | waiting_approval
  final String status;
  final String? detail;
  final bool busy;

  /// Last `error` event or failed request, shown above the composer.
  final String? lastError;
  final int? inputTokens;
  final int? outputTokens;
  final double? costEstimate;

  /// Approval ids with an `approval.decide` in flight.
  final Set<String> deciding;
  final bool sending;

  List<Approval> get pendingApprovals =>
      [for (final a in approvals.values) if (a.isPending) a];

  ChatState copyWith({
    bool? loading,
    Object? loadError = _keep,
    Session? session,
    List<Message>? messages,
    Map<String, ToolRun>? toolRuns,
    Map<String, Approval>? approvals,
    String? status,
    Object? detail = _keep,
    bool? busy,
    Object? lastError = _keep,
    int? inputTokens,
    int? outputTokens,
    Object? costEstimate = _keep,
    Set<String>? deciding,
    bool? sending,
  }) =>
      ChatState(
        loading: loading ?? this.loading,
        loadError: loadError == _keep ? this.loadError : loadError as String?,
        session: session ?? this.session,
        messages: messages ?? this.messages,
        toolRuns: toolRuns ?? this.toolRuns,
        approvals: approvals ?? this.approvals,
        status: status ?? this.status,
        detail: detail == _keep ? this.detail : detail as String?,
        busy: busy ?? this.busy,
        lastError: lastError == _keep ? this.lastError : lastError as String?,
        inputTokens: inputTokens ?? this.inputTokens,
        outputTokens: outputTokens ?? this.outputTokens,
        costEstimate:
            costEstimate == _keep ? this.costEstimate : costEstimate as double?,
        deciding: deciding ?? this.deciding,
        sending: sending ?? this.sending,
      );

  /// Replaces everything with a `session.history` result.
  ChatState withHistory(SessionHistory h) => copyWith(
        loading: false,
        loadError: null,
        session: h.session,
        messages: h.messages,
        toolRuns: {for (final r in h.toolRuns) r.id: r},
        approvals: {for (final a in h.approvals) a.id: a},
        busy: h.busy,
        status: h.busy ? (status == 'idle' ? 'thinking' : status) : 'idle',
      );

  int get _latestTimestamp {
    var t = 0;
    for (final m in messages) {
      if (m.createdAt > t) t = m.createdAt;
    }
    for (final r in toolRuns.values) {
      if (r.createdAt > t) t = r.createdAt;
    }
    return t;
  }

  /// Folds one event (§6.3) into the state. Events for other sessions are
  /// ignored.
  ChatState applyEvent(RpcEvent e, String sessionId) {
    if (e.sessionId != sessionId) return this;
    final d = e.data;
    switch (e.name) {
      case 'status':
        final s = d['status'] is String ? d['status'] as String : 'idle';
        return copyWith(
          status: s,
          detail: d['detail'] is String ? d['detail'] as String : null,
          busy: s != 'idle',
        );
      case 'delta':
        final id = d['message_id'];
        final text = d['delta'];
        if (id is! String || text is! String) return this;
        final reasoning = d['reasoning'] == true;
        final list = List<Message>.of(messages);
        final i = list.indexWhere((m) => m.id == id);
        if (i < 0) {
          list.add(Message(
            id: id,
            sessionId: sessionId,
            role: 'assistant',
            content: reasoning ? '' : text,
            reasoning: reasoning ? text : null,
            createdAt: _latestTimestamp + 1,
            streaming: true,
          ));
        } else {
          final m = list[i];
          list[i] = reasoning
              ? m.copyWith(reasoning: (m.reasoning ?? '') + text)
              : m.copyWith(content: m.content + text);
        }
        return copyWith(messages: list);
      case 'message':
        final raw = d['message'];
        if (raw is! Map) return this;
        final msg = Message.fromJson(raw.cast<String, dynamic>());
        final list = List<Message>.of(messages);
        final i = list.indexWhere((m) => m.id == msg.id);
        if (i < 0) {
          list.add(msg);
        } else {
          list[i] = msg;
        }
        return copyWith(messages: list);
      case 'tool_run':
        final raw = d['run'];
        if (raw is! Map) return this;
        final run = ToolRun.fromJson(raw.cast<String, dynamic>());
        return copyWith(toolRuns: {...toolRuns, run.id: run});
      case 'approval':
        final raw = d['approval'];
        if (raw is! Map) return this;
        final a = Approval.fromJson(raw.cast<String, dynamic>());
        return copyWith(
          approvals: {...approvals, a.id: a},
          deciding: a.isPending ? deciding : ({...deciding}..remove(a.id)),
        );
      case 'usage':
        return copyWith(
          inputTokens: (d['input_tokens'] as num?)?.toInt(),
          outputTokens: (d['output_tokens'] as num?)?.toInt(),
          costEstimate: (d['cost_estimate'] as num?)?.toDouble(),
        );
      case 'error':
        return copyWith(lastError: describeError(d['error']));
    }
    return this;
  }
}

const _keep = Object();

String describeError(Object? e) {
  if (e is String) return e;
  if (e is Map) {
    final code = e['code'];
    final msg = e['message'];
    if (code is String) {
      return RpcError(code, msg is String ? msg : '').readable;
    }
    if (msg is String) return msg;
  }
  return e?.toString() ?? 'Unknown error';
}

/// One row in the chat list.
sealed class TimelineItem {
  const TimelineItem(this.at);
  final int at;
}

class MessageItem extends TimelineItem {
  MessageItem(this.message) : super(message.createdAt);
  final Message message;
}

class ToolRunItem extends TimelineItem {
  ToolRunItem(this.run, this.approval) : super(run.createdAt);
  final ToolRun run;
  final Approval? approval;
}

/// Approvals whose tool run is unknown to us still get a card.
class ApprovalItem extends TimelineItem {
  ApprovalItem(this.approval) : super(approval.createdAt);
  final Approval approval;
}

/// Messages and tool runs in time order. Tool-result messages and empty
/// assistant messages (tool calls only) are covered by the tool-run cards.
List<TimelineItem> buildTimeline(ChatState s) {
  final items = <TimelineItem>[];
  for (final m in s.messages) {
    if (m.role == 'tool' || m.role == 'system') continue;
    if (m.role == 'assistant' &&
        m.content.trim().isEmpty &&
        (m.reasoning ?? '').trim().isEmpty &&
        !m.streaming) {
      continue;
    }
    items.add(MessageItem(m));
  }
  final byRun = <String, Approval>{
    for (final a in s.approvals.values) a.toolRunId: a,
  };
  for (final r in s.toolRuns.values) {
    items.add(ToolRunItem(r, byRun[r.id]));
  }
  for (final a in s.approvals.values) {
    if (!s.toolRuns.containsKey(a.toolRunId) && a.isPending) {
      items.add(ApprovalItem(a));
    }
  }
  // Stable sort: equal timestamps keep insertion order (messages first).
  final indexed = items.asMap().entries.toList()
    ..sort((a, b) {
      final c = a.value.at.compareTo(b.value.at);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}
