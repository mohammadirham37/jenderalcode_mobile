import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';

/// Permission modes a session can be switched to with `session.set_policy`.
const policyModes = ['safe', 'balanced', 'yolo'];

/// Session.policy_mode for display; null means the profile default.
String policyLabel(String? mode) => switch (mode) {
      'safe' => 'Safe',
      'balanced' => 'Balanced',
      'yolo' => 'Full access',
      _ => 'Default',
    };

String policyDescription(String mode) => switch (mode) {
      'safe' => 'Asks before every change and command.',
      'balanced' => 'Asks before commands and risky changes.',
      'yolo' => 'Runs everything without asking.',
      _ => '',
    };

const fullAccessConfirmTitle = 'Turn on Full access?';
const fullAccessConfirmText =
    'Full access lets the agent run any command and change any file in this '
    'project without asking. Anyone holding this phone can then control your '
    'computer. Turn on Full access?';

/// Whether [mode] can be picked at all, given the desktop's capabilities.
bool policyModeAllowed(String mode, Capabilities caps) =>
    mode != 'yolo' || caps.fullAccess;

/// `session.set_policy` (§6.5): returns the updated session.
Future<Session> setSessionPolicy(RpcClient rpc, String sessionId, String mode) async {
  final r = await rpc.call('session.set_policy', {'session_id': sessionId, 'mode': mode});
  final raw = r['session'];
  if (raw is! Map) throw const RpcError('internal', 'The desktop sent no session.');
  return Session.fromJson(raw.cast<String, dynamic>());
}

sealed class PolicyChange {
  const PolicyChange();
}

class PolicyChanged extends PolicyChange {
  const PolicyChanged(this.session);
  final Session session;
}

/// Nothing was sent: same mode, user cancelled, or the mode is not allowed.
class PolicyNotSent extends PolicyChange {
  const PolicyNotSent(this.reason);
  final String reason;
}

class PolicyFailed extends PolicyChange {
  const PolicyFailed(this.error);
  final RpcError error;
}

/// The gate in front of `session.set_policy`: Full access is only sent when
/// the desktop allows it and the user confirmed [fullAccessConfirmText].
Future<PolicyChange> changePolicy({
  required String mode,
  required String? current,
  required Capabilities caps,
  required Future<bool> Function() confirmFullAccess,
  required Future<Session> Function(String mode) send,
}) async {
  if (!policyModes.contains(mode)) return const PolicyNotSent('unknown');
  if (mode == current) return const PolicyNotSent('unchanged');
  if (!policyModeAllowed(mode, caps)) return const PolicyNotSent('not_allowed');
  if (mode == 'yolo' && !await confirmFullAccess()) {
    return const PolicyNotSent('cancelled');
  }
  try {
    return PolicyChanged(await send(mode));
  } on RpcError catch (e) {
    return PolicyFailed(e);
  }
}
