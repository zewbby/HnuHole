import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;

import 'package:flutter/foundation.dart';

import '../posts/post_api.dart';
import 'dm_protocol.dart';
import 'dm_store.dart';

part 'dm_chat_controller.dart';
part 'dm_governance_controller.dart';

typedef DmStoreFactory = Future<DmStore> Function(String account);

/// A controller owns one authorized session window. Its store is permanently
/// bound to the account; async replies never consult a newly selected account.
class DmController extends ChangeNotifier {
  DmController({
    required this.api,
    required this.openStore,
    this.onUnauthorized,
    this.onUnavailable,
    this.onMetadata,
    this.onIncoming,
    this.purgeStore,
    this.chatEnabled = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final DmApi api;
  final bool chatEnabled;
  final DmStoreFactory openStore;
  final Future<void> Function(String account)? purgeStore;
  final Future<void> Function(List<Map<String, dynamic>>, String account)?
  onIncoming;
  final void Function(String, String?)? onUnauthorized;
  final void Function(String)? onUnavailable;
  final Future<void> Function(String, DateTime, bool Function())? onMetadata;
  DmStore? _store;
  String? _account, _token;
  int _epoch = 0;
  int _bindingGeneration = 0;
  String? _bindingAccount;
  final _pendingBinds = <String, Set<Future<void>>>{};
  final _retirements = <String, Set<Future<void>>>{};
  final _closedAccounts = <String>{};
  final _purgedAccounts = <String>{};
  final _purging = <String, Future<void>>{};
  bool _disposed = false;
  bool Function()? _authorized;
  List<String> _identities = [];
  Future<void>? _syncing;
  Timer? _timer;
  Timer? _retryTimer;
  final _waitClocks = <String, (String, Stopwatch)>{};
  List<Map<String, dynamic>> conversations = [];
  String? error;
  String? _operationError;
  bool get available =>
      _store != null && _authorized?.call() == true && !_disposed;
  String get scope => '${_account ?? ''}:$_epoch';
  String? get accountId => _account;

  Future<void> bind({
    required String account,
    required String token,
    required List<String> identities,
    required bool Function() isCurrent,
  }) {
    if (_closedAccounts.contains(account)) return Future.value();
    _bindingAccount = account;
    final task = _bind(
      account: account,
      token: token,
      identities: identities,
      isCurrent: isCurrent,
    );
    (_pendingBinds[account] ??= {}).add(task);
    return task.whenComplete(() {
      _pendingBinds[account]?.remove(task);
      if (_pendingBinds[account]?.isEmpty == true) {
        _pendingBinds.remove(account);
      }
    });
  }

  Future<void> _bind({
    required String account,
    required String token,
    required List<String> identities,
    required bool Function() isCurrent,
  }) async {
    final binding = ++_bindingGeneration;
    await _disconnect();
    if (_disposed ||
        binding != _bindingGeneration ||
        !isCurrent() ||
        _closedAccounts.contains(account)) {
      return;
    }
    final epoch = ++_epoch;
    _account = account;
    _token = token;
    _identities = List.of(identities);
    _authorized = isCurrent;
    DmStore? opened;
    try {
      final store = await openStore(account);
      opened = store;
      if (!_current(epoch)) {
        await store.close();
        return;
      }
      await store.reconcileIdentities(identities);
      if (!_current(epoch)) {
        await store.close();
        return;
      }
      _store = store;
      await _refreshDirectory(epoch, store);
      if (!_current(epoch)) return;
      _notify();
      _timer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(sync()),
      );
      await sync();
    } catch (_) {
      if (opened != null && !identical(opened, _store)) await opened.close();
      if (_current(epoch)) {
        error = '私信本地保存不可用，输入不会被清除';
        _notify();
      }
    }
  }

  bool _current(int epoch) =>
      !_disposed && _epoch == epoch && _authorized?.call() == true;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> detach() async {
    _bindingGeneration++;
    _bindingAccount = null;
    await _disconnect();
  }

  Future<void> _disconnect() {
    final account = _account;
    final task = _disconnectWindow();
    if (account == null) return task;
    (_retirements[account] ??= {}).add(task);
    return task.whenComplete(() {
      _retirements[account]?.remove(task);
      if (_retirements[account]?.isEmpty == true) _retirements.remove(account);
    });
  }

  Future<void> _disconnectWindow() async {
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _waitClocks.clear();
    _authorized = null;
    final store = _store;
    _store = null;
    _account = null;
    _token = null;
    _identities = [];
    conversations = [];
    error = null;
    _operationError = null;
    _notify();
    // Drain the old window before opening a new store and starting another loop.
    await _syncing;
    await store?.close();
  }

  /// AuthFlows calls this only after a durable authoritative CLOSED result.
  /// Mark closed before the first await so pending opens and late callbacks
  /// cannot publish the old account, even if another account is already bound.
  Future<void> purgeClosedAccount(String account) {
    if (account.isEmpty) throw ArgumentError.value(account, 'account');
    if (_purgedAccounts.contains(account)) return Future.value();
    final running = _purging[account];
    if (running != null) return running;
    _closedAccounts.add(account);
    final task = _purgeClosedAccount(account);
    _purging[account] = task;
    return task.whenComplete(() => _purging.remove(account));
  }

  Future<void> _purgeClosedAccount(String account) async {
    if (_account == account || _bindingAccount == account) await detach();
    await Future.wait(List.of(_pendingBinds[account] ?? <Future<void>>{}));
    await Future.wait(List.of(_retirements[account] ?? <Future<void>>{}));
    if (purgeStore != null) {
      await purgeStore!(account);
    } else {
      final store = await openStore(account);
      try {
        await store.purgeClosedAccount();
      } finally {
        await store.close();
      }
    }
    _purgedAccounts.add(account);
  }

  Future<void> sync() {
    if (_syncing != null) return _syncing!;
    if (!available) return Future.value();
    final task = _synchronize(_epoch, _store!, _token!);
    _syncing = task;
    return task.whenComplete(() => _syncing = null);
  }

  String _requestClass(String method, String path) {
    if (method == 'POST' &&
        path.startsWith('commands/') &&
        path.endsWith('/close')) {
      return 'close';
    }
    if (method == 'PUT' &&
        (path.startsWith('commands/') || path.startsWith('chat/images/'))) {
      return 'send';
    }
    if (path == 'ack' ||
        path == 'read' ||
        path.startsWith('commands/') ||
        path.startsWith('chat/operations/') ||
        path.startsWith('governance/blocks/')) {
      return 'control';
    }
    return 'read';
  }

  Future<int> _remaining(String kind, DmStore store) async {
    final wait = await store.cooldown(kind);
    if (wait == null) return 0;
    final key = '${wait.recordedAt.toIso8601String()}:${wait.seconds}';
    var measured = _waitClocks[kind];
    if (measured == null || measured.$1 != key) {
      measured = (key, Stopwatch()..start());
      _waitClocks[kind] = measured;
    }
    final wall = wait.remaining(_clock());
    final monotonic = (wait.seconds - measured.$2.elapsed.inSeconds).clamp(
      0,
      wait.seconds,
    );
    return wall < monotonic ? wall : monotonic;
  }

  Future<void> _wakeAfterCooldown(int epoch, DmStore store) async {
    int? next;
    for (final kind in ['send', 'read', 'control', 'close']) {
      final delay = await _remaining(kind, store);
      if (delay > 0 && (next == null || delay < next)) next = delay;
    }
    if (!_current(epoch)) return;
    _retryTimer?.cancel();
    _retryTimer = next == null
        ? null
        : Timer(Duration(seconds: next), () {
            if (_current(epoch)) unawaited(sync());
          });
  }

  Future<Map<String, dynamic>> _request(
    int epoch,
    String token,
    String method,
    String path, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (!_current(epoch)) throw StateError('DM window expired');
    final store = _store!;
    final kind = _requestClass(method, path);
    final wait = await _remaining(kind, store);
    if (!_current(epoch)) throw StateError('DM window expired');
    if (wait > 0) {
      throw PostFailure(
        kind: PostFailureKind.rejected,
        statusCode: 429,
        code: 'RATE_LIMITED',
        retryAfterSeconds: wait,
      );
    }
    late PostResponse<Map<String, dynamic>> response;
    try {
      response = await api.dmRequest(
        token,
        method,
        path,
        body: body,
        query: query,
      );
    } on PostFailure catch (e) {
      if (_current(epoch) &&
          (e.statusCode == 429 || e.code == 'SHARED_RATE_UNAVAILABLE')) {
        await store.defer(
          kind,
          _clock(),
          e.statusCode == 429 ? e.retryAfterSeconds ?? 1 : 5,
        );
      }
      // Contact/foreground requests share the same fail-closed boundary as
      // background sync; do not leave history visible until the next poll.
      if (_current(epoch)) _stopForFailure(e, token);
      rethrow;
    }
    if (!_current(epoch)) throw StateError('DM window expired');
    await onMetadata?.call(
      token,
      response.sessionExpiresAt,
      () => _current(epoch),
    );
    if (!_current(epoch)) throw StateError('DM window expired');
    return response.value;
  }

  Future<void> _syncWork(
    int epoch,
    DmStore store,
    String token,
    Map<String, dynamic> row,
  ) async {
    try {
      final id = row['_id'] as String;
      final state = row['_state'] as String;
      if (state == 'queued' || state == 'unknown') {
        final intent = Map<String, Object>.from(row['intent'] as Map);
        if (!_identities.contains(intent['identityId'])) return;
        if (!_current(epoch)) return;
        var receipt = await _request(epoch, token, 'GET', 'commands/$id');
        final latest = await store.get(id);
        final hidden = latest?['_kind'] == 'hidden_message';
        if (hidden && latest?['_state'] != 'unknown') return;
        if (hidden &&
            (receipt['state'] == 'ABSENT' ||
                receipt['state'] == 'FAILED' &&
                    receipt['errorCode'] != 'COMMAND_CLOSED' &&
                    (receipt['attempt'] as int) < (intent['attempt'] as int))) {
          // An account-locked server anchor orders with every delayed original
          // PUT. It can confirm SENT or permanently close an unsent original;
          // it never replays the erased body or claims to retract a sent one.
          receipt = await _request(
            epoch,
            token,
            'POST',
            'commands/$id/close',
            body: {'attempt': intent['attempt'] as int},
          );
        }
        if (hidden &&
            receipt['state'] != 'SENT' &&
            !(receipt['state'] == 'FAILED' &&
                (receipt['errorCode'] == 'COMMAND_CLOSED' ||
                    (receipt['attempt'] as int) >=
                        (intent['attempt'] as int)))) {
          return;
        }
        if (!hidden &&
            (receipt['state'] == 'ABSENT' ||
                receipt['state'] == 'FAILED' &&
                    receipt['errorCode'] != 'COMMAND_CLOSED' &&
                    (receipt['attempt'] as int) < (intent['attempt'] as int))) {
          if (await store.hasPredecessor(id)) return;
          final image = row['messageType'] == 'IMAGE';
          if (image) {
            intent['data'] = base64Encode(
              await store.photo(
                intent['mediaId'] as String,
                senderId: intent['identityId'] as String,
              ),
            );
          }
          // The user may delete while original bytes are being read.
          final beforeSend = await store.get(id);
          if (beforeSend == null || beforeSend['_kind'] == 'hidden_message') {
            return;
          }
          if (await _remaining('send', store) > 0 || !_current(epoch)) return;
          if (beforeSend['_state'] == 'queued') {
            await store.transition(id, 'queued', 'unknown');
          }
          if (!_current(epoch)) return;
          receipt = await _request(
            epoch,
            token,
            'PUT',
            image ? 'chat/images/$id' : 'commands/$id',
            body: intent,
          );
        }
        if (!_current(epoch)) return;
        if ((!hidden &&
                receipt['attempt'] != intent['attempt'] &&
                receipt['errorCode'] != 'COMMAND_CLOSED') ||
            !{'SENT', 'FAILED'}.contains(receipt['state'])) {
          throw const FormatException('DM attempt mismatch');
        }
        final current = await store.get(id);
        if (current == null) return;
        await store.transition(
          id,
          current['_state'] as String,
          receipt['state'] == 'SENT' ? 'sent' : 'failed',
          receipt: receipt,
        );
        if (chatEnabled && receipt['state'] == 'SENT') {
          await store.enforceDeleteFor(id);
          final control = await store.get('retracted:${receipt['messageId']}');
          if (control != null) {
            await store.applyControls([control], await store.controlCursor());
          }
        }
        if (chatEnabled) await store.eraseHiddenResolved(id);
      } else {
        final read = state == 'read_pending';
        await _request(
          epoch,
          token,
          'POST',
          read ? 'read' : 'ack',
          body: {
            'messageIds': [id],
          },
        );
        if (!_current(epoch)) return;
        await store.transition(id, state, read ? 'read' : 'inbox');
        if (chatEnabled) await store.eraseHiddenResolved(id);
      }
    } on PostFailure catch (e) {
      if (_current(epoch)) {
        _stopForFailure(e, token);
        if (e.code == 'SHARED_RATE_UNAVAILABLE') {
          _operationError = '服务暂不可用，已保存消息稍后重试';
        } else if (e.statusCode != 429) {
          _operationError = '部分消息仍在核对，原内容已保存';
        }
      }
    } catch (_) {
      if (_current(epoch)) _operationError = '部分消息仍在核对，原内容已保存';
    }
  }

  Future<void> _drainSends(int epoch, DmStore store, String token) async {
    try {
      final attempted = <String>{};
      // Re-read after a settled predecessor so normal bursts drain immediately.
      // Unknown predecessors are attempted only once per round and keep their
      // pair blocked; they never prevent another pair or incoming ACK work.
      for (var batch = 0; batch < store.maxPendingSends; batch++) {
        final rows = (await store.work())
            .where(
              (r) =>
                  {'queued', 'unknown'}.contains(r['_state']) &&
                  !attempted.contains(r['_id']),
            )
            .toList();
        if (rows.isEmpty) break;
        for (final row in rows) {
          if (!_current(epoch)) return;
          attempted.add(row['_id'] as String);
          await _syncWork(epoch, store, token, row);
        }
      }
    } catch (_) {
      if (_current(epoch)) _operationError = '部分消息仍在核对，原内容已保存';
    }
  }

  Future<void> _synchronize(int epoch, DmStore store, String token) async {
    final incoming = <Map<String, dynamic>>[];
    final account = _account!;
    // Independent lanes: a slow/unknown PUT cannot stop durable receive + ACK.
    final outgoing = _drainSends(epoch, store, token);
    try {
      if (chatEnabled) {
        try {
          await _chatBeforeSync(epoch, store, token);
        } on PostFailure catch (e) {
          if (e.kind == PostFailureKind.unauthorized ||
              e.kind == PostFailureKind.unavailable) {
            rethrow;
          }
        } catch (_) {}
      }
      for (final row in await store.work()) {
        if (!_current(epoch)) return;
        if (!{'queued', 'unknown'}.contains(row['_state'])) {
          await _syncWork(epoch, store, token, row);
        }
      }
      if (!_current(epoch)) return;
      final pending = await _request(
        epoch,
        token,
        'GET',
        chatEnabled ? 'chat/pending' : 'pending',
      );
      final items = (pending['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (items.any((item) => !_identities.contains(item['identityId']))) {
        throw const FormatException('Wrong pending identity');
      }
      if (items.isNotEmpty) {
        if (!_current(epoch)) return;
        final durableIds = <String>[];
        if (chatEnabled) {
          for (final item in items) {
            if (!_current(epoch)) return;
            try {
              if (await store.deliverySuppressed(item)) {
                durableIds.add(item['messageId']);
                continue;
              }
              final previous = await store.get(item['messageId']);
              if (previous != null) {
                durableIds.add(item['messageId']);
                continue;
              }
              if (item['kind'] == 'IMAGE') {
                final media = await _request(
                  epoch,
                  token,
                  'GET',
                  'chat/media/${item['messageId']}',
                );
                if (media['messageId'] != item['messageId'] ||
                    media['mediaId'] != (item['media'] as Map)['mediaId'] ||
                    media['sha256'] != (item['media'] as Map)['sha256']) {
                  throw const FormatException('Mismatched private image');
                }
                final bytes = base64Decode(media['data'] as String);
                if (bytes.length != media['byteLength'] ||
                    hashes.sha256.convert(bytes).toString() !=
                        media['sha256']) {
                  throw const FormatException('Damaged private image');
                }
                if (!_current(epoch)) return;
                await store.receivePhoto(item, bytes);
              } else {
                if (!_current(epoch)) return;
                await store.receive([item]);
              }
              if (!_current(epoch)) return;
              if (await store.get(item['messageId']) != null) {
                incoming.add(item);
              }
              durableIds.add(item['messageId']);
            } on PostFailure catch (e) {
              if (e.kind == PostFailureKind.unauthorized ||
                  e.kind == PostFailureKind.unavailable) {
                rethrow;
              }
              _operationError = '部分聊天记录未保存，请清理空间或恢复连接后重试';
            } catch (_) {
              _operationError = '部分聊天记录未保存，请清理空间或恢复连接后重试';
            }
          }
        } else {
          final unseen = <Map<String, dynamic>>[];
          for (final item in items) {
            if (await store.get(item['messageId']) == null) unseen.add(item);
          }
          if (!_current(epoch)) return;
          await store.receive(items);
          if (!_current(epoch)) return;
          for (final item in unseen) {
            if (await store.get(item['messageId']) != null) incoming.add(item);
          }
          durableIds.addAll(items.map((e) => e['messageId'] as String));
        }
        if (!_current(epoch)) return;
        if (durableIds.isNotEmpty) {
          await _request(
            epoch,
            token,
            'POST',
            'ack',
            body: {'messageIds': durableIds},
          );
          if (!_current(epoch)) return;
          for (final item in items) {
            if (!durableIds.contains(item['messageId'])) continue;
            final row = await store.get(item['messageId']);
            if (!_current(epoch)) return;
            if (row?['_state'] == 'received') {
              await store.transition(item['messageId'], 'received', 'inbox');
            }
          }
        }
      }
      for (final identity in _identities) {
        var after = '';
        do {
          final page = await _request(
            epoch,
            token,
            'GET',
            chatEnabled ? 'chat/conversations' : 'conversations',
            query: {
              'identityId': identity,
              if (after.isNotEmpty) 'after': after,
            },
          );
          final rows = (page['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          if (rows.any((e) => e['identityId'] != identity)) {
            throw const FormatException('DM identity mismatch');
          }
          if (!_current(epoch)) return;
          if (chatEnabled) {
            await store.saveChatConversations(rows);
          } else {
            await store.saveConversations(rows);
          }
          if (rows.length < 100) break;
          final next = rows.last['id'] as String;
          if (next.compareTo(after) <= 0) {
            throw const FormatException('DM pagination stalled');
          }
          after = next;
        } while (_current(epoch));
      }
      if (chatEnabled) await _chatControls(epoch, store, token);
      if (!_current(epoch)) return;
      error = _operationError;
      _operationError = null;
    } on PostFailure catch (e) {
      if (!_current(epoch)) return;
      _stopForFailure(e, token);
      if (!_current(epoch)) return;
      error = '连接暂不可用，已保存内容将在恢复后继续核对';
    } catch (_) {
      if (_current(epoch)) {
        error = '同步暂未完成，已保存内容保留，稍后自动核对';
      }
    } finally {
      if (_current(epoch)) {
        try {
          await _refreshDirectory(epoch, store);
          if (_current(epoch) && incoming.isNotEmpty) {
            await onIncoming?.call(incoming, account);
          }
        } catch (_) {}
        if (_current(epoch)) {
          await _wakeAfterCooldown(epoch, store);
          _notify();
        }
      }
      await outgoing;
      if (_current(epoch)) {
        // The outgoing lane can finish after the receive lane published its
        // status. Publish its late operation notice only inside the same epoch;
        // an authorization failure may already have suspended this window.
        if (_operationError != null) {
          error = _operationError;
          _operationError = null;
        }
        await _wakeAfterCooldown(epoch, store);
        await _refreshDirectory(epoch, store);
        _notify();
      }
    }
  }

  void _stopForFailure(PostFailure failure, String token) {
    if (failure.kind == PostFailureKind.unavailable &&
        failure.statusCode == 503 &&
        failure.code == 'SHARED_RATE_UNAVAILABLE') {
      return;
    }
    if (failure.kind == PostFailureKind.unauthorized) {
      _suspendWindow();
      onUnauthorized?.call(token, failure.code);
    } else if (failure.kind == PostFailureKind.unavailable) {
      _suspendWindow();
      onUnavailable?.call(token);
    }
  }

  void _suspendWindow() {
    _epoch++;
    _authorized = null;
    _timer?.cancel();
    _timer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    conversations = [];
    error = '当前会话暂不可用，请恢复授权后查看私信';
    _notify();
  }

  Future<void> _refreshDirectory(int epoch, DmStore store) async {
    final directory = (await store.conversations())
        .where((v) => _identities.contains(v['identityId']))
        .toList();
    for (final v in directory) {
      final local = await store.history(v['identityId'], v['peerId'], limit: 1);
      if (!_current(epoch)) return;
      if (local.isNotEmpty) {
        final last = local.single;
        v['localPreview'] = last['recalled'] == true
            ? '消息已撤回'
            : last['messageType'] == 'IMAGE'
            ? '[图片]'
            : last['outgoing'] == true
            ? (last['intent'] as Map)['text']
            : last['text'];
        v['localOrdinal'] = last['_ordinal'];
        v['localState'] = last['outgoing'] == true ? last['_state'] : null;
      }
    }
    directory.sort(
      (a, b) =>
          (b['pinned'] == true ? 1 : 0).compareTo(
                a['pinned'] == true ? 1 : 0,
              ) !=
              0
          ? (b['pinned'] == true ? 1 : 0).compareTo(a['pinned'] == true ? 1 : 0)
          : ((b['localOrdinal'] as int?) ?? 0).compareTo(
              (a['localOrdinal'] as int?) ?? 0,
            ),
    );
    if (!_current(epoch)) return;
    conversations = directory;
  }

  Future<bool> send(Map<String, Object> intent, {String peerName = ''}) async {
    if (!available || !_identities.contains(intent['identityId'])) return false;
    final epoch = _epoch;
    final store = _store!;
    try {
      await store.enqueue(intent, peerName: peerName);
      if (!_current(epoch)) return false;
      // The enqueue commit is authoritative. A later projection/read failure
      // must not report enqueue failure and invite a duplicate user send.
      try {
        await _refreshDirectory(epoch, store);
      } catch (_) {}
      if (!_current(epoch)) return false;
      _notify();
      unawaited(sync());
      return true;
    } on DmQueueFull {
      if (_current(epoch)) {
        error = '发送队列已满，请等待或取消未发送消息，输入已保留';
        _notify();
      }
      return false;
    } catch (_) {
      if (_current(epoch)) {
        error = '保存失败，请保留输入并重试';
        _notify();
      }
      return false;
    }
  }

  Future<void> retry(String id) async {
    if (!available) return;
    final epoch = _epoch;
    final store = _store!;
    try {
      await store.retry(id);
      if (_current(epoch)) {
        _notify();
        await sync();
      }
    } catch (_) {
      if (_current(epoch)) {
        error = '原消息暂时无法重试';
        _notify();
      }
    }
  }

  Future<Map<String, dynamic>> contact(String post, String comment) async {
    if (!available) throw StateError('DM unavailable');
    return _request(
      _epoch,
      _token!,
      'GET',
      'contact',
      query: {'postId': post, if (comment.isNotEmpty) 'commentId': comment},
    );
  }

  Future<bool> saveDraft(String own, String peer, String text) async {
    if (!available || !_identities.contains(own)) return false;
    final epoch = _epoch;
    try {
      await _store!.saveDraft(own, peer, text);
      return _current(epoch);
    } catch (_) {
      if (_current(epoch)) {
        error = '草稿保存失败，请保留当前页面';
        _notify();
      }
      return false;
    }
  }

  Future<String> draft(String own, String peer) async {
    if (!available || !_identities.contains(own)) return '';
    final epoch = _epoch;
    final value = await _store!.draft(own, peer);
    return _current(epoch) ? value : '';
  }

  Future<Map<String, dynamic>?> message(String id) async {
    if (!available) return null;
    final epoch = _epoch;
    final row = await _store!.get(id);
    return _current(epoch) ? row : null;
  }

  Future<List<Map<String, dynamic>>> history(
    String own,
    String peer, {
    int? before,
  }) async {
    if (!available || !_identities.contains(own)) return [];
    final epoch = _epoch;
    final rows = await _store!.history(own, peer, before: before);
    return _current(epoch) ? rows : [];
  }

  Future<void> visible(List<String> ids) async {
    if (!available || ids.isEmpty) return;
    final epoch = _epoch;
    try {
      final changed = await _store!.markVisible(ids);
      if (changed && _current(epoch)) unawaited(sync());
    } catch (_) {
      if (_current(epoch)) {
        error = '阅读状态尚未保存';
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(detach());
    super.dispose();
  }
}
