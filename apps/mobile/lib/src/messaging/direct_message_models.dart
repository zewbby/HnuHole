import 'package:flutter/foundation.dart';

enum DmSendState { sent, sending, unknown, failed }

enum DmMessageAction { copy, delete, recall, report, retry }

/// Local history only. This is not an API for downloading cloud chat archives.
enum DmHistoryState { complete, available, loading, failed }

@immutable
class DmHistoryRequest {
  const DmHistoryRequest({required this.scopeKey, this.before});
  final String scopeKey;
  final String? before;
}

@immutable
class DmIdentity {
  const DmIdentity({required this.id, required this.name});
  final String id, name;
}

@immutable
class DmImage {
  const DmImage({
    required this.id,
    required this.description,
    this.state,
    this.canRecall,
  });
  final String id, description;
  final DmSendState? state;
  final bool? canRecall;
}

@immutable
class DmMessage {
  const DmMessage({
    required this.id,
    required this.outgoing,
    required this.time,
    this.text = '',
    this.images = const [],
    this.state = DmSendState.sent,
    this.canRecall = false,
    this.recalled = false,
    this.reeditableText,
    this.dayLabel,
    this.visibleMessageIds = const [],
  });
  final String id, time, text;
  final bool outgoing, canRecall, recalled;
  final List<DmImage> images;
  final DmSendState state;
  final String? reeditableText;

  /// Calendar label supplied by the local repository in the user's timezone.
  final String? dayLabel;
  final List<String> visibleMessageIds;

  DmMessage copyWith({DmSendState? state, bool? recalled}) => DmMessage(
    id: id,
    outgoing: outgoing,
    time: time,
    text: text,
    images: images,
    state: state ?? this.state,
    canRecall: canRecall,
    recalled: recalled ?? this.recalled,
    reeditableText: reeditableText,
    dayLabel: dayLabel,
  );
}

/// This scope is an identity pair, never the currently selected inbox identity.
/// No private account identifier is rendered by the presentation layer.
@immutable
class DmConversationView {
  const DmConversationView({
    required this.scopeKey,
    required this.recipient,
    required this.sourceTitle,
    required this.messages,
    this.selfIdentity,
    this.privateNote,
    this.identityLocked = true,
    this.firstContact = false,
    this.firstTextAccepted = false,
    this.canSend = true,
    this.sourceDeleted = false,
    this.localSaveFailed = false,
    this.draftText = '',
    this.draftRevision = 0,
    this.dayLabel = '',
    this.historyState = DmHistoryState.complete,
    this.historyCursor,
    this.firstUnreadMessageId,
    this.draftImages = const [],
  });
  final String scopeKey, sourceTitle, draftText, dayLabel;
  final DmIdentity recipient;
  final DmIdentity? selfIdentity;
  final String? privateNote;
  final List<DmMessage> messages;
  final List<DmImage> draftImages;
  final bool identityLocked, firstContact, firstTextAccepted, canSend;
  final bool sourceDeleted, localSaveFailed;

  /// Increment only for an explicit restore/re-edit, not every poll response.
  final int draftRevision;
  final DmHistoryState historyState;
  final String? historyCursor, firstUnreadMessageId;
  bool get waitingForReply => firstContact && firstTextAccepted;
}

@immutable
class DmSendIntent {
  const DmSendIntent({
    required this.scopeKey,
    required this.identityId,
    required this.text,
    required this.images,
  });
  final String scopeKey, identityId, text;
  final List<DmImage> images;
}

@immutable
class DmMessageTarget {
  const DmMessageTarget({
    required this.scopeKey,
    required this.messageId,
    this.imageId,
  });
  final String scopeKey, messageId;
  final String? imageId;
}
