part of 'dm_controller.dart';

extension DmGovernanceController on DmController {
  Future<List<Map<String, dynamic>>> blocks() async {
    if (!available) return [];
    final epoch = _epoch;
    final result = await _request(epoch, _token!, 'GET', 'governance/blocks');
    return (result['items'] as List)
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
  }

  Future<void> setBlocked(
    String identity,
    String conversation,
    bool blocked,
  ) async {
    if (!available || !chatEnabled) return;
    final epoch = _epoch;
    await _store!.enqueueOperation({
      'operation': 'BLOCK',
      'identityId': identity,
      'conversationId': conversation,
      'blocked': blocked,
    });
    if (_current(epoch)) await sync();
  }
}
