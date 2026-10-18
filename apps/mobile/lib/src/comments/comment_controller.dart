import 'package:flutter/foundation.dart';

import '../posts/post_protocol.dart';
import 'comment_api.dart';
import 'comment_models.dart';

/// Independent task core. The application supplies a durable account-scoped
/// journal, authenticated API and the unified notification rendering adapter.
class CommentController extends ChangeNotifier {
  CommentController({required this.api, required this.journal});
  final CommentApi api;
  final CommentJournal journal;
  String? _accountId;
  int _epoch = 0;
  bool _disposed = false;
  bool _ready = false;
  final _entries = <String, CommentJournalEntry>{};
  final _busy = <String>{};
  final _retiredIdentities = <String>{};
  final _resolved = <CommentTask>[];
  final _usedCommands = <String>{};
  final _knownTasks = <String>{};
  final _executingCommands = <String>{};
  Future<void> _writes = Future.value();
  String? get accountId => _accountId;
  bool get ready => _ready;
  List<CommentJournalEntry> get entries => List.unmodifiable(_entries.values);
  List<CommentTask> get resolvedTasks => List.unmodifiable(_resolved);

  Future<void> _write(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _put(String account, CommentJournalEntry entry) =>
      _write(() => journal.put(account, entry));
  Future<void> _remove(String account, String id) =>
      _write(() => journal.remove(account, id));

  /// No notification UI is implemented here. Only settled, authoritative FAILED
  /// tasks are projected, and opening a projection never removes its task.
  List<CommentFailureNotice> get failures => List.unmodifiable([
    for (final entry in _entries.values)
      if (entry.transport == CommentTransportState.settled &&
          entry.task?.state == CommentTaskState.failed &&
          !entry.identityDeleted &&
          !_retiredIdentities.contains(entry.intent.binding.identityId))
        CommentFailureNotice(
          localId: entry.localId,
          task: entry.task!,
          content: entry.content,
        ),
  ]);

  bool _current(String account, int epoch) =>
      !_disposed && _accountId == account && _epoch == epoch;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> activate(String? account) async {
    if (_disposed) return;
    if (account != null) PostProtocol.resourceId(account);
    final epoch = ++_epoch;
    _accountId = account;
    _ready = false;
    _entries.clear();
    _retiredIdentities.clear();
    _resolved.clear();
    _usedCommands.clear();
    _knownTasks.clear();
    _changed();
    if (account == null) return;
    await _writes;
    final loaded = await journal.read(account);
    if (!_current(account, epoch)) return;
    final loadedIds = <String>{}, loadedCommands = <String>{};
    for (final entry in loaded) {
      _validateEntry(entry);
      if (!loadedIds.add(entry.localId) ||
          entry.usedCommandIds.any((id) => !loadedCommands.add(id))) {
        throw const FormatException('Duplicate journal task or command');
      }
    }
    for (final entry in loaded) {
      // A crashed SENDING is unknown, not evidence of server acceptance.
      _entries[entry.localId] = entry.withState(
        entry.intent.operation == CommentOperation.create &&
                entry.rejectionCode != null
            ? CommentTransportState.settled
            : CommentTransportState.unknown,
      );
      _knownTasks.add(entry.localId);
      _usedCommands.addAll(entry.usedCommandIds);
      if (entry.identityDeleted) {
        _retiredIdentities.add(entry.intent.binding.identityId);
      }
    }
    _ready = true;
    _changed();
    for (final id in _entries.keys.toList()) {
      if (!_current(account, epoch)) return;
      await reconcile(id);
    }
  }

  Future<void> submit({
    required String taskId,
    required String commandId,
    required CommentBinding binding,
    required CommentContent content,
  }) async {
    final account = _accountId;
    if (account == null || _disposed || !_ready) {
      throw StateError('No ready account');
    }
    if (_knownTasks.contains(taskId) ||
        _busy.contains('$account:$_epoch:$taskId')) {
      throw StateError('The task already exists');
    }
    if (_retiredIdentities.contains(binding.identityId)) {
      throw const CommentIdentityDeleted();
    }
    if (_entries.values.any(
      (entry) =>
          entry.intent.operation == CommentOperation.create &&
          entry.rejectionCode != null &&
          entry.intent.binding.postId == binding.postId,
    )) {
      throw StateError('Release the rejected input before a new submission');
    }
    final intent = CommentIntent(
      commandId: commandId,
      taskId: taskId,
      operation: CommentOperation.create,
      binding: binding,
      content: content,
    );
    if (_usedCommands.contains(commandId)) {
      throw StateError('A new task requires a fresh command ID');
    }
    final entry = CommentJournalEntry(
      localId: taskId,
      intent: intent,
      transport: CommentTransportState.sending,
    );
    await _execute(entry, account, _epoch);
  }

  Future<void> retry({
    required String localId,
    required String commandId,
    required CommentContent content,
  }) async {
    final old = _editable(localId);
    final task = old.task!;
    if (!task.canRetry || task.attemptVersion == 2147483647) {
      throw StateError('The task cannot be retried');
    }
    final intent = CommentIntent(
      commandId: commandId,
      taskId: task.taskId,
      operation: CommentOperation.retry,
      binding: task.binding,
      expectedAttemptVersion: task.attemptVersion,
      content: content,
    );
    _freshCommand(old, intent);
    await _execute(
      CommentJournalEntry(
        localId: localId,
        intent: intent,
        transport: CommentTransportState.sending,
        task: task,
        retainedContent: content,
        usedCommandIds: [...old.usedCommandIds, commandId],
      ),
      _accountId!,
      _epoch,
    );
  }

  /// Only confirmed FAILED tasks can be abandoned. An unknown abandon command
  /// must be queried before the content may be moved to a new target.
  Future<void> abandon({
    required String localId,
    required String commandId,
  }) async {
    final old = _editable(localId);
    final task = old.task!;
    if (!task.canAbandon) throw StateError('The task cannot be abandoned');
    final intent = CommentIntent(
      commandId: commandId,
      taskId: task.taskId,
      operation: CommentOperation.abandon,
      binding: task.binding,
      expectedAttemptVersion: task.attemptVersion,
    );
    _freshCommand(old, intent);
    await _execute(
      CommentJournalEntry(
        localId: localId,
        intent: intent,
        transport: CommentTransportState.sending,
        task: task,
        retainedContent: old.content,
        usedCommandIds: [...old.usedCommandIds, commandId],
      ),
      _accountId!,
      _epoch,
    );
  }

  CommentJournalEntry _editable(String id) {
    final entry = _entries[id];
    if (_accountId == null ||
        !_ready ||
        entry == null ||
        entry.transport != CommentTransportState.settled ||
        entry.task?.state != CommentTaskState.failed ||
        _retiredIdentities.contains(entry.intent.binding.identityId)) {
      throw StateError('Only a confirmed failed task can be changed');
    }
    return entry;
  }

  /// The host may install the returned value only into this currently open
  /// post's temporary editor, checking its route generation after the await.
  /// No network send or target change happens here.
  Future<CommentRejectedInput?> releaseRejected({
    required String localId,
    required String activePostId,
  }) async {
    final account = _accountId, epoch = _epoch, entry = _entries[localId];
    if (!_ready ||
        account == null ||
        entry == null ||
        entry.intent.operation != CommentOperation.create ||
        entry.rejectionCode == null ||
        entry.transport != CommentTransportState.settled ||
        entry.intent.binding.postId != activePostId ||
        entry.content == null ||
        entry.identityDeleted) {
      throw StateError('No rejected input for this open post');
    }
    final key = '$account:$epoch:$localId';
    if (!_busy.add(key)) throw StateError('Task operation in progress');
    try {
      await _remove(account, localId);
      if (!_current(account, epoch) ||
          _retiredIdentities.contains(entry.intent.binding.identityId) ||
          _entries[localId] != entry) {
        return null;
      }
      _entries.remove(localId);
      _changed();
      return CommentRejectedInput(
        binding: entry.intent.binding,
        content: entry.content!,
      );
    } finally {
      _busy.remove(key);
    }
  }

  void _freshCommand(CommentJournalEntry old, CommentIntent next) {
    if (_usedCommands.contains(next.commandId)) {
      throw StateError('A new mutation requires a fresh command ID');
    }
  }

  Future<void> _execute(
    CommentJournalEntry entry,
    String account,
    int epoch,
  ) async {
    final key = '$account:$epoch:${entry.localId}';
    if (!_busy.add(key)) {
      throw StateError('A task operation is already running');
    }
    final commandKey = '$account:$epoch:${entry.intent.commandId}';
    if (!_executingCommands.add(commandKey)) {
      _busy.remove(key);
      throw StateError('A command is already running');
    }
    try {
      // This is deliberately outside the transport catch: failed persistence
      // must propagate and must never make a network request.
      await _put(account, entry);
      if (!_current(account, epoch)) return;
      if (_retiredIdentities.contains(entry.intent.binding.identityId)) {
        await _remove(account, entry.localId);
        return;
      }
      _entries[entry.localId] = entry;
      _knownTasks.add(entry.localId);
      _usedCommands.addAll(entry.usedCommandIds);
      _changed();
      try {
        final task = await api.execute(entry.intent);
        if (!_current(account, epoch)) return;
        await _apply(account, epoch, entry, task, commandResult: true);
      } on CommentCommandRejected catch (rejection) {
        if (_current(account, epoch)) {
          await _recordRejection(account, epoch, entry, rejection.code);
        }
      } on CommentIdentityDeleted {
        if (_current(account, epoch)) {
          await _identityDeleted(
            entry.intent.binding.identityId,
            confirmedUnpublishedTaskId: entry.localId,
          );
        }
      } catch (_) {
        if (_current(account, epoch) &&
            !_retiredIdentities.contains(entry.intent.binding.identityId)) {
          await _unknown(account, epoch, entry);
        }
      }
    } finally {
      _busy.remove(key);
      _executingCommands.remove(commandKey);
    }
  }

  Future<void> reconcile(String localId) async {
    final account = _accountId, entry = _entries[localId], epoch = _epoch;
    if (account == null || entry == null || _disposed) return;
    final key = '$account:$epoch:$localId';
    if (!_busy.add(key)) return;
    try {
      if (entry.rejectionCode != null) {
        if (entry.intent.operation != CommentOperation.create) {
          await _queryRejectedTask(account, epoch, entry);
        }
        return;
      }
      try {
        final task = await api.query(entry.intent);
        if (!_current(account, epoch)) {
          return;
        }
        if (task == null) {
          if (!_knownFailure(entry)) await _unknown(account, epoch, entry);
        } else {
          await _apply(account, epoch, entry, task, commandResult: false);
        }
      } on CommentCommandRejected catch (rejection) {
        if (_current(account, epoch)) {
          await _recordRejection(account, epoch, entry, rejection.code);
        }
      } on CommentIdentityDeleted {
        if (_current(account, epoch)) {
          await _identityDeleted(
            entry.intent.binding.identityId,
            confirmedUnpublishedTaskId: entry.localId,
          );
        }
      } catch (_) {
        if (_current(account, epoch) && !_knownFailure(entry)) {
          await _unknown(account, epoch, entry);
        }
      }
    } finally {
      _busy.remove(key);
    }
  }

  static bool _knownFailure(CommentJournalEntry entry) =>
      entry.transport == CommentTransportState.settled &&
      entry.task?.state == CommentTaskState.failed;

  Future<void> _recordRejection(
    String account,
    int epoch,
    CommentJournalEntry entry,
    String code,
  ) async {
    if (!_current(account, epoch)) return;
    if (_retiredIdentities.contains(entry.intent.binding.identityId)) {
      await _clearTask(account, epoch, entry.localId);
      return;
    }
    final rejected = entry.rejected(code);
    await _put(account, rejected);
    if (!_current(account, epoch) ||
        _retiredIdentities.contains(entry.intent.binding.identityId)) {
      return;
    }
    _entries[entry.localId] = rejected;
    _changed();
    if (entry.intent.operation != CommentOperation.create) {
      await _queryRejectedTask(account, epoch, rejected);
    }
  }

  Future<void> _queryRejectedTask(
    String account,
    int epoch,
    CommentJournalEntry entry,
  ) async {
    try {
      final task = await api.queryTask(
        taskId: entry.intent.taskId,
        binding: entry.intent.binding,
      );
      if (!_current(account, epoch) || task == null) return;
      await _apply(account, epoch, entry, task, commandResult: false);
    } on CommentIdentityDeleted {
      if (_current(account, epoch)) {
        await _identityDeleted(
          entry.intent.binding.identityId,
          confirmedUnpublishedTaskId: entry.localId,
        );
      }
    } catch (_) {
      // The command is rejected, but its task state still requires a fresh
      // authoritative read. A cached old failure cannot unlock another retry.
    }
  }

  Future<void> _unknown(
    String account,
    int epoch,
    CommentJournalEntry entry,
  ) async {
    final unknown = _retiredIdentities.contains(entry.intent.binding.identityId)
        ? entry.redactDeletedIdentity()
        : entry.withState(CommentTransportState.unknown);
    if (!_current(account, epoch) || !_entries.containsKey(entry.localId)) {
      return;
    }
    _entries[entry.localId] = unknown;
    _changed();
    await _put(account, unknown);
  }

  Future<void> _apply(
    String account,
    int epoch,
    CommentJournalEntry entry,
    CommentTask task, {
    required bool commandResult,
  }) async {
    if (!_current(account, epoch) || !_entries.containsKey(entry.localId)) {
      return;
    }
    final intent = entry.intent;
    if (task.taskId != intent.taskId || !task.binding.sameAs(intent.binding)) {
      throw const FormatException('Comment task ownership or target changed');
    }
    final rejectedMutation =
        entry.rejectionCode != null &&
        intent.operation != CommentOperation.create;
    final expected = rejectedMutation
        ? intent.expectedAttemptVersion!
        : switch (intent.operation) {
            CommentOperation.create => 1,
            CommentOperation.retry => intent.expectedAttemptVersion! + 1,
            CommentOperation.abandon => intent.expectedAttemptVersion!,
          };
    // Querying an old FAILED snapshot cannot prove whether an unknown retry or
    // abandon was accepted. Keep querying the mutation, never resend it.
    if (task.attemptVersion < expected ||
        intent.operation == CommentOperation.abandon &&
            task.state == CommentTaskState.failed &&
            !commandResult &&
            !rejectedMutation) {
      await _unknown(account, epoch, entry);
      return;
    }
    if ((!rejectedMutation && task.attemptVersion != expected) ||
        intent.operation == CommentOperation.abandon &&
            !rejectedMutation &&
            task.state != CommentTaskState.abandoned &&
            task.state != CommentTaskState.published) {
      throw const FormatException('Unexpected comment attempt result');
    }
    final current = _entries[entry.localId]?.task;
    if (current != null &&
        task.attemptVersion == current.attemptVersion &&
        current.state == CommentTaskState.failed &&
        (task.state == CommentTaskState.accepted ||
            task.state == CommentTaskState.published ||
            task.state == CommentTaskState.abandoned &&
                intent.operation != CommentOperation.abandon &&
                !rejectedMutation)) {
      // A failed attempt cannot become accepted/published at the same version.
      return;
    }
    if (current != null &&
        (task.attemptVersion < current.attemptVersion ||
            task.attemptVersion == current.attemptVersion &&
                current.state == CommentTaskState.published &&
                task.state != CommentTaskState.published)) {
      throw const FormatException('Comment task regressed');
    }
    if (task.state == CommentTaskState.published ||
        task.state == CommentTaskState.abandoned) {
      await _remove(account, entry.localId);
      if (!_current(account, epoch)) return;
      _entries.remove(entry.localId);
      _resolved.add(task);
      _changed();
      return;
    }
    if (_retiredIdentities.contains(intent.binding.identityId)) {
      if (task.state == CommentTaskState.failed) {
        await _clearTask(account, epoch, entry.localId);
      } else {
        await _unknown(account, epoch, entry);
      }
      return;
    }
    final next = entry.withState(CommentTransportState.settled, snapshot: task);
    await _put(account, next);
    if (!_current(account, epoch) ||
        _retiredIdentities.contains(intent.binding.identityId)) {
      return;
    }
    _entries[entry.localId] = next;
    _changed();
  }

  /// Call only after the host has confirmed deletion for this active account.
  /// Published content remains public. Unknown sends are retained for result
  /// queries; known failures are cleared without offering retry or an archive.
  Future<void> identityDeleted(String identityId) =>
      _identityDeleted(identityId);

  Future<void> _identityDeleted(
    String identityId, {
    String? confirmedUnpublishedTaskId,
  }) async {
    PostProtocol.resourceId(identityId);
    final account = _accountId, epoch = _epoch;
    if (account == null || _disposed) return;
    _retiredIdentities.add(identityId);
    final affected = [
      for (final e in _entries.values)
        if (e.intent.binding.identityId == identityId) e,
    ];
    final failed = <String>{};
    for (final entry in affected) {
      if (entry.localId == confirmedUnpublishedTaskId ||
          entry.rejectionCode != null &&
              entry.intent.operation == CommentOperation.create ||
          entry.transport == CommentTransportState.settled &&
              entry.task?.state == CommentTaskState.failed) {
        failed.add(entry.localId);
        _entries.remove(entry.localId);
      } else {
        // Clear every payload before the first await, including other tasks
        // whose journal cleanup may take time.
        _entries[entry.localId] = entry.redactDeletedIdentity();
      }
    }
    _changed();
    for (final entry in affected) {
      await _put(account, entry.redactDeletedIdentity());
      if (!_current(account, epoch)) return;
      if (failed.contains(entry.localId)) {
        await _remove(account, entry.localId);
      }
    }
    for (final entry in affected) {
      if (!_current(account, epoch)) return;
      if (!failed.contains(entry.localId)) await reconcile(entry.localId);
    }
  }

  Future<void> _clearTask(String account, int epoch, String id) async {
    if (!_current(account, epoch)) return;
    final old = _entries.remove(id);
    _changed();
    if (old != null &&
        _retiredIdentities.contains(old.intent.binding.identityId)) {
      // If the physical remove fails, only a content-free tombstone may remain.
      await _put(account, old.redactDeletedIdentity());
    }
    await _remove(account, id);
  }

  static void _validateEntry(CommentJournalEntry entry) {
    for (final id in entry.usedCommandIds) {
      PostProtocol.commandId(id);
    }
    if (entry.localId != entry.intent.taskId ||
        entry.rejectionCode != null &&
            (!RegExp(r'^[A-Z][A-Z0-9_]{0,63}$')
                    .hasMatch(entry.rejectionCode!) ||
                entry.intent.operation == CommentOperation.create &&
                    entry.task != null) ||
        entry.usedCommandIds.toSet().length != entry.usedCommandIds.length ||
        !entry.usedCommandIds.contains(entry.intent.commandId) ||
        entry.identityDeleted &&
            (!entry.intent.reconciliationOnly ||
                entry.retainedContent != null ||
                entry.intent.content != null) ||
        entry.task != null &&
            (entry.task!.taskId != entry.intent.taskId ||
                !entry.task!.binding.sameAs(entry.intent.binding))) {
      throw const FormatException('Invalid comment journal entry');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _entries.clear();
    _resolved.clear();
    super.dispose();
  }
}
