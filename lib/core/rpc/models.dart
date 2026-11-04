// Application types from docs/protocol.md §6.4. Unknown fields are ignored;
// missing optional fields become null.

typedef Json = Map<String, dynamic>;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
String? _strOrNull(Object? v) => v is String ? v : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
Json _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Json> _list(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
    ];

class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.lastOpenedAt,
    required this.isGitRepo,
  });
  final String id;
  final String name;
  final String rootPath;
  final int lastOpenedAt;
  final bool isGitRepo;

  factory Workspace.fromJson(Json j) => Workspace(
        id: _str(j['id']),
        name: _str(j['name']),
        rootPath: _str(j['root_path']),
        lastOpenedAt: _int(j['last_opened_at']),
        isGitRepo: j['is_git_repo'] == true,
      );

  static List<Workspace> listFrom(Object? v) =>
      [for (final j in _list(v)) Workspace.fromJson(j)];
}

class Session {
  const Session({
    required this.id,
    required this.workspaceId,
    required this.title,
    this.agentProfileId,
    this.providerId,
    this.modelName,
    this.policyMode,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
  });
  final String id;
  final String workspaceId;
  final String title;
  final String? agentProfileId;
  final String? providerId;
  final String? modelName;

  /// `safe`, `balanced`, `yolo`, or null (profile default).
  final String? policyMode;
  final int createdAt;
  final int updatedAt;
  final int messageCount;

  bool get isYolo => policyMode == 'yolo';

  factory Session.fromJson(Json j) => Session(
        id: _str(j['id']),
        workspaceId: _str(j['workspace_id']),
        title: _str(j['title']),
        agentProfileId: _strOrNull(j['agent_profile_id']),
        providerId: _strOrNull(j['provider_id']),
        modelName: _strOrNull(j['model_name']),
        policyMode: _strOrNull(j['policy_mode']),
        createdAt: _int(j['created_at']),
        updatedAt: _int(j['updated_at']),
        messageCount: _int(j['message_count']),
      );

  static List<Session> listFrom(Object? v) =>
      [for (final j in _list(v)) Session.fromJson(j)];
}

class ToolCall {
  const ToolCall({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;

  /// Raw JSON string as produced by the model.
  final String arguments;

  factory ToolCall.fromJson(Json j) => ToolCall(
        id: _str(j['id']),
        name: _str(j['name']),
        arguments: _str(j['arguments']),
      );
}

class Message {
  const Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.reasoning,
    required this.createdAt,
    this.streaming = false,
  });
  final String id;
  final String sessionId;

  /// `system`, `user`, `assistant` or `tool`.
  final String role;
  final String content;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final String? reasoning;
  final int createdAt;

  /// Local only: built from `delta` events, not yet replaced by `message`.
  final bool streaming;

  factory Message.fromJson(Json j) => Message(
        id: _str(j['id']),
        sessionId: _str(j['session_id']),
        role: _str(j['role'], 'assistant'),
        content: _str(j['content']),
        toolCalls: [for (final c in _list(j['tool_calls'])) ToolCall.fromJson(c)],
        toolCallId: _strOrNull(j['tool_call_id']),
        toolName: _strOrNull(j['tool_name']),
        reasoning: _strOrNull(j['reasoning']),
        createdAt: _int(j['created_at']),
      );

  Message copyWith({String? content, String? reasoning}) => Message(
        id: id,
        sessionId: sessionId,
        role: role,
        content: content ?? this.content,
        toolCalls: toolCalls,
        toolCallId: toolCallId,
        toolName: toolName,
        reasoning: reasoning ?? this.reasoning,
        createdAt: createdAt,
        streaming: streaming,
      );

  static List<Message> listFrom(Object? v) =>
      [for (final j in _list(v)) Message.fromJson(j)];
}

class ToolRun {
  const ToolRun({
    required this.id,
    required this.sessionId,
    this.messageId,
    required this.toolName,
    required this.status,
    required this.args,
    this.resultSummary,
    this.error,
    this.approvalId,
    required this.createdAt,
    this.finishedAt,
  });
  final String id;
  final String sessionId;
  final String? messageId;
  final String toolName;

  /// pending | awaiting_approval | running | success | denied | error | cancelled
  final String status;
  final Json args;
  final String? resultSummary;
  final String? error;
  final String? approvalId;
  final int createdAt;
  final int? finishedAt;

  factory ToolRun.fromJson(Json j) => ToolRun(
        id: _str(j['id']),
        sessionId: _str(j['session_id']),
        messageId: _strOrNull(j['message_id']),
        toolName: _str(j['tool_name']),
        status: _str(j['status'], 'pending'),
        args: _map(j['args']),
        resultSummary: _strOrNull(j['result_summary']),
        error: _strOrNull(j['error']),
        approvalId: _strOrNull(j['approval_id']),
        createdAt: _int(j['created_at']),
        finishedAt: _intOrNull(j['finished_at']),
      );

  static List<ToolRun> listFrom(Object? v) =>
      [for (final j in _list(v)) ToolRun.fromJson(j)];
}

class Approval {
  const Approval({
    required this.id,
    required this.sessionId,
    required this.toolRunId,
    required this.kind,
    required this.description,
    this.preview,
    required this.status,
    required this.createdAt,
    this.decidedAt,
  });
  final String id;
  final String sessionId;
  final String toolRunId;
  final String kind;
  final String description;
  final String? preview;

  /// pending | approved | denied
  final String status;
  final int createdAt;
  final int? decidedAt;

  bool get isPending => status == 'pending';

  factory Approval.fromJson(Json j) => Approval(
        id: _str(j['id']),
        sessionId: _str(j['session_id']),
        toolRunId: _str(j['tool_run_id']),
        kind: _str(j['kind']),
        description: _str(j['description']),
        preview: _strOrNull(j['preview']),
        status: _str(j['status'], 'pending'),
        createdAt: _int(j['created_at']),
        decidedAt: _intOrNull(j['decided_at']),
      );

  Approval withStatus(String s) => Approval(
        id: id,
        sessionId: sessionId,
        toolRunId: toolRunId,
        kind: kind,
        description: description,
        preview: preview,
        status: s,
        createdAt: createdAt,
        decidedAt: decidedAt,
      );

  static List<Approval> listFrom(Object? v) =>
      [for (final j in _list(v)) Approval.fromJson(j)];
}

/// Result of `session.history`.
class SessionHistory {
  const SessionHistory({
    required this.session,
    required this.messages,
    required this.toolRuns,
    required this.approvals,
    required this.busy,
  });
  final Session session;
  final List<Message> messages;
  final List<ToolRun> toolRuns;
  final List<Approval> approvals;
  final bool busy;

  factory SessionHistory.fromJson(Json j) => SessionHistory(
        session: Session.fromJson(_map(j['session'])),
        messages: Message.listFrom(j['messages']),
        toolRuns: ToolRun.listFrom(j['tool_runs']),
        approvals: Approval.listFrom(j['approvals']),
        busy: j['busy'] == true,
      );
}

/// Result of `hello`.
class HelloResult {
  const HelloResult({required this.desktopVersion, required this.desktopName});
  final String desktopVersion;
  final String desktopName;
  factory HelloResult.fromJson(Json j) => HelloResult(
        desktopVersion: _str(j['desktop_version']),
        desktopName: _str(j['desktop_name']),
      );
}
