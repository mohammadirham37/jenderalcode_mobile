import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';

/// Shown in the emulator when the process ends.
const processExitedText = '[process exited]';

/// What the terminal screen knows about one attached terminal. Output itself
/// lives in the xterm emulator; [reduceAttach]/[reduceEvent] say what to
/// write to it.
class TermState {
  const TermState({
    this.info,
    this.attaching = false,
    this.attached = false,
    this.exited = false,
    this.exitCode,
    this.error,
    this.generation = 0,
    this.ctrlArmed = false,
  });

  final RemoteTerminal? info;
  final bool attaching;
  final bool attached;
  final bool exited;
  final int? exitCode;

  /// Last failed request (attach, input, resize, close).
  final String? error;

  /// Bumped on every successful attach: the screen starts a fresh emulator so
  /// the replayed scrollback is not drawn on top of the old screen.
  final int generation;

  /// Sticky Ctrl from the extra key bar: applies to the next key.
  final bool ctrlArmed;

  int get cols => info?.cols ?? 80;
  int get rows => info?.rows ?? 24;

  TermState copyWith({
    RemoteTerminal? info,
    bool? attaching,
    bool? attached,
    bool? exited,
    Object? exitCode = _keep,
    Object? error = _keep,
    int? generation,
    bool? ctrlArmed,
  }) =>
      TermState(
        info: info ?? this.info,
        attaching: attaching ?? this.attaching,
        attached: attached ?? this.attached,
        exited: exited ?? this.exited,
        exitCode: exitCode == _keep ? this.exitCode : exitCode as int?,
        error: error == _keep ? this.error : error as String?,
        generation: generation ?? this.generation,
        ctrlArmed: ctrlArmed ?? this.ctrlArmed,
      );
}

const _keep = Object();

/// A new state plus what to feed the emulator. [reset] means: start a new
/// emulator (sized [TermState.cols]×[TermState.rows]) before writing [output].
class TermUpdate {
  const TermUpdate(this.state, {this.output = '', this.reset = false});
  final TermState state;
  final String output;
  final bool reset;
}

/// `terminal.attach` answered: replay the scrollback into a fresh emulator.
TermUpdate reduceAttach(TermState s, Json result) {
  final raw = result['terminal'];
  final info = raw is Map ? RemoteTerminal.fromJson(raw.cast<String, dynamic>()) : s.info;
  final scrollback = result['scrollback'] is String ? result['scrollback'] as String : '';
  return TermUpdate(
    s.copyWith(
      info: info,
      attaching: false,
      attached: true,
      exited: false,
      exitCode: null,
      error: null,
      generation: s.generation + 1,
    ),
    output: scrollback,
    reset: true,
  );
}

/// Folds one `terminal.*` event (§6.3) for [terminalId]; others are ignored.
TermUpdate reduceEvent(TermState s, RpcEvent e, String terminalId) {
  final d = e.data;
  if (d['terminal_id'] != terminalId) return TermUpdate(s);
  switch (e.name) {
    case 'terminal.data':
      final data = d['data'];
      if (data is! String || data.isEmpty) return TermUpdate(s);
      return TermUpdate(s, output: data);
    case 'terminal.exit':
      if (s.exited) return TermUpdate(s);
      final code = d['code'];
      return TermUpdate(
        s.copyWith(exited: true, exitCode: code is num ? code.toInt() : null),
        output: '\r\n$processExitedText\r\n',
      );
    case 'terminal.resized':
      final cols = d['cols'];
      final rows = d['rows'];
      final info = s.info;
      if (cols is! num || rows is! num || info == null) return TermUpdate(s);
      return TermUpdate(s.copyWith(info: info.withSize(cols.toInt(), rows.toInt())));
  }
  return TermUpdate(s);
}
