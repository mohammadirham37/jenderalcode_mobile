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

/// What the desktop allows from the phone (§6.5). Older desktops send no
/// `capabilities`, which means neither.
class Capabilities {
  const Capabilities({required this.fullAccess, required this.terminal, this.edit = false});
  final bool fullAccess;
  final bool terminal;

  /// Writing actions: fs.write/create/delete/rename, git writes, checkpoint restore.
  final bool edit;

  static const none = Capabilities(fullAccess: false, terminal: false, edit: false);

  factory Capabilities.fromJson(Object? v) {
    final j = _map(v);
    return Capabilities(
      fullAccess: j['full_access'] == true,
      terminal: j['terminal'] == true,
      edit: j['edit'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Capabilities &&
      other.fullAccess == fullAccess &&
      other.terminal == terminal &&
      other.edit == edit;

  @override
  int get hashCode => Object.hash(fullAccess, terminal, edit);

  @override
  String toString() =>
      'Capabilities(full_access: $fullAccess, terminal: $terminal, edit: $edit)';
}

/// A running terminal on the desktop (§6.4 `Terminal`). Named so it does not
/// clash with the xterm emulator's `Terminal`.
class RemoteTerminal {
  const RemoteTerminal({
    required this.id,
    required this.title,
    required this.kind,
    required this.origin,
    this.workspaceId,
    required this.cols,
    required this.rows,
    this.bypass = false,
  });
  final String id;
  final String title;

  /// Agent CLI running with its bypass-permissions flags (§6.4).
  final bool bypass;

  /// `shell` or `agent`.
  final String kind;

  /// `desktop` (a tab on the desktop) or `remote` (opened from a phone).
  final String origin;
  final String? workspaceId;
  final int cols;
  final int rows;

  bool get isRemote => origin == 'remote';
  bool get isAgent => kind == 'agent';

  factory RemoteTerminal.fromJson(Json j) => RemoteTerminal(
        id: _str(j['id']),
        title: _str(j['title']),
        kind: _str(j['kind'], 'shell'),
        origin: _str(j['origin'], 'desktop'),
        workspaceId: _strOrNull(j['workspace_id']),
        cols: _int(j['cols']),
        rows: _int(j['rows']),
        bypass: j['bypass'] == true,
      );

  RemoteTerminal withSize(int cols, int rows) => RemoteTerminal(
        id: id,
        title: title,
        kind: kind,
        origin: origin,
        workspaceId: workspaceId,
        cols: cols,
        rows: rows,
        bypass: bypass,
      );

  static List<RemoteTerminal> listFrom(Object? v) =>
      [for (final j in _list(v)) RemoteTerminal.fromJson(j)];
}

/// Result of `hello`.
class HelloResult {
  const HelloResult({
    required this.desktopVersion,
    required this.desktopName,
    this.capabilities = Capabilities.none,
  });
  final String desktopVersion;
  final String desktopName;
  final Capabilities capabilities;
  factory HelloResult.fromJson(Json j) => HelloResult(
        desktopVersion: _str(j['desktop_version']),
        desktopName: _str(j['desktop_name']),
        capabilities: Capabilities.fromJson(j['capabilities']),
      );
}

bool? _boolOrNull(Object? v) => v is bool ? v : null;
double? _doubleOrNull(Object? v) => v is num ? v.toDouble() : null;

/// Agent profile (§6.4 `Agent`).
class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.mode,
    this.policyMode,
    required this.builtIn,
  });
  final String id;
  final String name;

  /// plan | build | review | custom
  final String mode;
  final String? policyMode;
  final bool builtIn;

  String get modeLabel => switch (mode) {
        'plan' => 'Plan',
        'build' => 'Build',
        'review' => 'Review',
        'custom' => 'Custom',
        _ => mode.isEmpty ? 'Custom' : mode,
      };

  factory Agent.fromJson(Json j) => Agent(
        id: _str(j['id']),
        name: _str(j['name']),
        mode: _str(j['mode'], 'custom'),
        policyMode: _strOrNull(j['policy_mode']),
        builtIn: j['built_in'] == true,
      );

  static List<Agent> listFrom(Object? v) => [for (final j in _list(v)) Agent.fromJson(j)];
}

/// §6.4 `Provider` (named so it does not clash with Riverpod).
class AiProvider {
  const AiProvider({required this.id, required this.name, required this.kind});
  final String id;
  final String name;
  final String kind;

  factory AiProvider.fromJson(Json j) =>
      AiProvider(id: _str(j['id']), name: _str(j['name']), kind: _str(j['kind']));

  static List<AiProvider> listFrom(Object? v) =>
      [for (final j in _list(v)) AiProvider.fromJson(j)];
}

class Model {
  const Model({
    required this.id,
    required this.providerId,
    required this.name,
    required this.displayName,
    this.vision,
    this.contextWindow,
  });
  final String id;
  final String providerId;

  /// The value for `session.set_model`'s `model_name`.
  final String name;
  final String displayName;

  /// Unknown capabilities stay null (desktop rule: never guess).
  final bool? vision;
  final int? contextWindow;

  String get label => displayName.isNotEmpty ? displayName : name;

  factory Model.fromJson(Json j) {
    final c = _map(j['capabilities']);
    return Model(
      id: _str(j['id']),
      providerId: _str(j['provider_id']),
      name: _str(j['name']),
      displayName: _str(j['display_name']),
      vision: _boolOrNull(c['vision']),
      contextWindow: _intOrNull(c['context_window']),
    );
  }

  static List<Model> listFrom(Object? v) => [for (final j in _list(v)) Model.fromJson(j)];
}

/// Result of `models.list`.
class ModelCatalog {
  const ModelCatalog({required this.providers, required this.models});
  final List<AiProvider> providers;
  final List<Model> models;

  factory ModelCatalog.fromJson(Json j) => ModelCatalog(
        providers: AiProvider.listFrom(j['providers']),
        models: Model.listFrom(j['models']),
      );

  /// Models per provider, in provider order; models of unknown providers last.
  List<(AiProvider, List<Model>)> get grouped {
    final out = <(AiProvider, List<Model>)>[];
    final known = <String>{};
    for (final p in providers) {
      known.add(p.id);
      final ms = [for (final m in models) if (m.providerId == p.id) m];
      if (ms.isNotEmpty) out.add((p, ms));
    }
    final rest = [for (final m in models) if (!known.contains(m.providerId)) m];
    if (rest.isNotEmpty) out.add((const AiProvider(id: '', name: 'Other', kind: ''), rest));
    return out;
  }

  Model? find(String? providerId, String? modelName) {
    if (modelName == null) return null;
    for (final m in models) {
      if (m.name == modelName && (providerId == null || m.providerId == providerId)) return m;
    }
    return null;
  }
}

/// Result of `session.usage`.
class SessionUsage {
  const SessionUsage({
    required this.totalInput,
    required this.totalOutput,
    this.totalCost,
    required this.requests,
    required this.lastInput,
    required this.lastOutput,
  });
  final int totalInput;
  final int totalOutput;
  final double? totalCost;
  final int requests;

  /// Input tokens of the latest request: roughly the current context fill.
  final int lastInput;
  final int lastOutput;

  factory SessionUsage.fromJson(Json j) => SessionUsage(
        totalInput: _int(j['total_input']),
        totalOutput: _int(j['total_output']),
        totalCost: _doubleOrNull(j['total_cost']),
        requests: _int(j['requests']),
        lastInput: _int(j['last_input']),
        lastOutput: _int(j['last_output']),
      );
}

class Skill {
  const Skill({required this.name, required this.description, required this.project});
  final String name;
  final String description;
  final bool project;

  factory Skill.fromJson(Json j) => Skill(
        name: _str(j['name']),
        description: _str(j['description']),
        project: j['project'] == true,
      );

  static List<Skill> listFrom(Object? v) => [for (final j in _list(v)) Skill.fromJson(j)];
}

class Checkpoint {
  const Checkpoint({
    required this.id,
    required this.sessionId,
    required this.relPath,
    required this.existed,
    required this.isDir,
    required this.createdAt,
  });
  final String id;
  final String sessionId;
  final String relPath;

  /// false: the agent created the file; restoring deletes it.
  final bool existed;
  final bool isDir;
  final int createdAt;

  factory Checkpoint.fromJson(Json j) => Checkpoint(
        id: _str(j['id']),
        sessionId: _str(j['session_id']),
        relPath: _str(j['rel_path']),
        existed: j['existed'] == true,
        isDir: j['is_dir'] == true,
        createdAt: _int(j['created_at']),
      );

  static List<Checkpoint> listFrom(Object? v) =>
      [for (final j in _list(v)) Checkpoint.fromJson(j)];
}

class FileEntry {
  const FileEntry({required this.path, required this.name, required this.isDir, this.size});
  final String path;
  final String name;
  final bool isDir;
  final int? size;

  factory FileEntry.fromJson(Json j) => FileEntry(
        path: _str(j['path']),
        name: _str(j['name']),
        isDir: j['is_dir'] == true,
        size: _intOrNull(j['size']),
      );

  static List<FileEntry> listFrom(Object? v) =>
      [for (final j in _list(v)) FileEntry.fromJson(j)];
}

/// §6.4 `StatusKind`. Unknown strings map to [other].
enum StatusKind {
  unmodified,
  modified,
  added,
  deleted,
  renamed,
  copied,
  untracked,
  ignored,
  other;

  static StatusKind parse(Object? v) =>
      StatusKind.values.where((k) => k.name == v).firstOrNull ?? StatusKind.other;

  /// One-letter code like `git status --short`.
  String get letter => switch (this) {
        unmodified => ' ',
        modified => 'M',
        added => 'A',
        deleted => 'D',
        renamed => 'R',
        copied => 'C',
        untracked => '?',
        ignored => '!',
        other => '·',
      };
}

class FileStatus {
  const FileStatus({required this.path, required this.index, required this.worktree});
  final String path;
  final StatusKind index;
  final StatusKind worktree;

  /// Has staged changes (index differs from HEAD).
  bool get isStaged =>
      index != StatusKind.unmodified &&
      index != StatusKind.untracked &&
      index != StatusKind.ignored;

  /// Has unstaged changes, including untracked files.
  bool get isUnstaged => worktree != StatusKind.unmodified && worktree != StatusKind.ignored;

  factory FileStatus.fromJson(Json j) => FileStatus(
        path: _str(j['path']),
        index: StatusKind.parse(j['index']),
        worktree: StatusKind.parse(j['worktree']),
      );

  static List<FileStatus> listFrom(Object? v) =>
      [for (final j in _list(v)) FileStatus.fromJson(j)];
}

class Commit {
  const Commit({
    required this.hash,
    required this.shortHash,
    required this.subject,
    required this.author,
    required this.timestamp,
  });
  final String hash;
  final String shortHash;
  final String subject;
  final String author;

  /// As sent by the desktop (unit not specified in §6.4; see [timestampMs]).
  final int timestamp;

  /// Milliseconds, treating values below 1e12 as seconds.
  int get timestampMs => timestamp < 1000000000000 ? timestamp * 1000 : timestamp;

  factory Commit.fromJson(Json j) => Commit(
        hash: _str(j['hash']),
        shortHash: _str(j['short_hash']),
        subject: _str(j['subject']),
        author: _str(j['author']),
        timestamp: _int(j['timestamp']),
      );

  static List<Commit> listFrom(Object? v) => [for (final j in _list(v)) Commit.fromJson(j)];
}

class Branch {
  const Branch({required this.name, required this.current});
  final String name;
  final bool current;

  factory Branch.fromJson(Json j) => Branch(name: _str(j['name']), current: j['current'] == true);

  static List<Branch> listFrom(Object? v) => [for (final j in _list(v)) Branch.fromJson(j)];
}

/// Agent CLI preset (§6.9 `AgentCliInfo`).
class AgentCliInfo {
  const AgentCliInfo({
    required this.id,
    required this.name,
    required this.command,
    required this.installed,
    required this.hasBypass,
    required this.hasResume,
  });
  final String id;
  final String name;
  final String command;
  final bool installed;
  final bool hasBypass;
  final bool hasResume;

  factory AgentCliInfo.fromJson(Json j) => AgentCliInfo(
        id: _str(j['id']),
        name: _str(j['name']),
        command: _str(j['command']),
        installed: j['installed'] == true,
        hasBypass: j['has_bypass'] == true,
        hasResume: j['has_resume'] == true,
      );

  static List<AgentCliInfo> listFrom(Object? v) =>
      [for (final j in _list(v)) AgentCliInfo.fromJson(j)];
}

/// §6.9 `AgentUsageReport.status`. Unknown strings map to [error].
enum AgentUsageStatus {
  ok('ok'),
  notInstalled('not installed'),
  notSignedIn('not signed in'),
  expired('expired'),
  unavailable('unavailable'),
  error('error');

  const AgentUsageStatus(this.label);
  final String label;

  static AgentUsageStatus parse(Object? v) => switch (v) {
        'ok' => ok,
        'not_installed' => notInstalled,
        'not_signed_in' => notSignedIn,
        'expired' => expired,
        'unavailable' => unavailable,
        _ => error,
      };
}

class UsageWindow {
  const UsageWindow({required this.label, this.usedPercent, this.resetsAt, this.detail});
  final String label;
  final double? usedPercent;

  /// Epoch milliseconds.
  final int? resetsAt;
  final String? detail;

  factory UsageWindow.fromJson(Json j) => UsageWindow(
        label: _str(j['label']),
        usedPercent: _doubleOrNull(j['used_percent']),
        resetsAt: _intOrNull(j['resets_at']),
        detail: _strOrNull(j['detail']),
      );

  static List<UsageWindow> listFrom(Object? v) =>
      [for (final j in _list(v)) UsageWindow.fromJson(j)];
}

class AgentUsageReport {
  const AgentUsageReport({
    required this.id,
    required this.name,
    required this.status,
    this.plan,
    this.account,
    this.windows = const [],
    this.note,
    this.updatedAt,
  });
  final String id;
  final String name;
  final AgentUsageStatus status;
  final String? plan;
  final String? account;
  final List<UsageWindow> windows;
  final String? note;
  final int? updatedAt;

  factory AgentUsageReport.fromJson(Json j) => AgentUsageReport(
        id: _str(j['id']),
        name: _str(j['name']),
        status: AgentUsageStatus.parse(j['status']),
        plan: _strOrNull(j['plan']),
        account: _strOrNull(j['account']),
        windows: UsageWindow.listFrom(j['windows']),
        note: _strOrNull(j['note']),
        updatedAt: _intOrNull(j['updated_at']),
      );

  static List<AgentUsageReport> listFrom(Object? v) =>
      [for (final j in _list(v)) AgentUsageReport.fromJson(j)];
}
