import '../posts/post_protocol.dart';
import '../posts/post_upload_models.dart';

/// Private, owner-only sending identity and exact content target.
class CommentBinding {
  CommentBinding({
    required this.postId,
    required this.identityId,
    this.rootCommentId,
    this.targetCommentId,
  }) {
    PostProtocol.resourceId(postId);
    PostProtocol.resourceId(identityId);
    if ((rootCommentId == null) != (targetCommentId == null)) {
      throw const FormatException('A reply requires a root and exact target');
    }
    if (rootCommentId != null) PostProtocol.resourceId(rootCommentId!);
    if (targetCommentId != null) PostProtocol.resourceId(targetCommentId!);
  }
  final String postId, identityId;
  final String? rootCommentId, targetCommentId;

  bool sameAs(CommentBinding other) =>
      postId == other.postId &&
      identityId == other.identityId &&
      rootCommentId == other.rootCommentId &&
      targetCommentId == other.targetCommentId;
}

/// The host owns encrypted image bytes. Never persist picker paths here.
class CommentImage {
  CommentImage({required this.blobId, required this.selection}) {
    PostProtocol.resourceId(blobId);
  }
  final String blobId;
  final PostImageSelection selection;
}

class CommentContent {
  CommentContent({required this.body, this.image}) {
    if (body.isNotEmpty || image == null) PostContentRules.validateBody(body);
  }
  final String body;
  final CommentImage? image;
}

enum CommentTaskState { accepted, published, failed, abandoned }

/// Client transport state is independent of the server's authoritative state.
enum CommentTransportState { sending, unknown, settled }

enum CommentOperation { create, retry, abandon }

class CommentTask {
  CommentTask({
    required this.taskId,
    required this.binding,
    required this.attemptVersion,
    required this.state,
    required this.contentAvailable,
    required this.canRetry,
    required this.canAbandon,
    this.commentId,
    this.failureCode,
  }) {
    PostProtocol.resourceId(taskId);
    PostProtocol.version(attemptVersion);
    if (commentId != null) PostProtocol.resourceId(commentId!);
    if ((state == CommentTaskState.published) != (commentId != null) ||
        (state == CommentTaskState.failed) != (failureCode != null) ||
        canRetry && (!contentAvailable || state != CommentTaskState.failed) ||
        canAbandon && state != CommentTaskState.failed ||
        state == CommentTaskState.abandoned && contentAvailable) {
      throw const FormatException('Inconsistent comment task');
    }
  }
  final String taskId;
  final CommentBinding binding;
  final int attemptVersion;
  final CommentTaskState state;
  final bool contentAvailable, canRetry, canAbandon;
  final String? commentId, failureCode;
}

/// A command is immutable once journaled, including across process restarts.
class CommentIntent {
  CommentIntent({
    required this.commandId,
    required this.taskId,
    required this.operation,
    required this.binding,
    this.expectedAttemptVersion,
    this.content,
    this.reconciliationOnly = false,
  }) {
    PostProtocol.commandId(commandId);
    PostProtocol.resourceId(taskId);
    if (expectedAttemptVersion != null) {
      PostProtocol.version(expectedAttemptVersion!);
    }
    if (reconciliationOnly && content != null ||
        (operation == CommentOperation.create
            ? expectedAttemptVersion != null ||
                  !reconciliationOnly && content == null
            : expectedAttemptVersion == null ||
                  !reconciliationOnly &&
                      (operation == CommentOperation.retry) !=
                          (content != null))) {
      throw const FormatException('Invalid comment command');
    }
  }
  final String commandId, taskId;
  final CommentOperation operation;
  final CommentBinding binding;
  final int? expectedAttemptVersion;
  final CommentContent? content;
  final bool reconciliationOnly;
  CommentIntent withoutContent() => CommentIntent(
    commandId: commandId,
    taskId: taskId,
    operation: operation,
    binding: binding,
    expectedAttemptVersion: expectedAttemptVersion,
    reconciliationOnly: true,
  );
}

class CommentJournalEntry {
  CommentJournalEntry({
    required this.localId,
    required this.intent,
    required this.transport,
    this.task,
    this.retainedContent,
    List<String>? usedCommandIds,
    this.identityDeleted = false,
    this.rejectionCode,
  }) : usedCommandIds = List.unmodifiable(usedCommandIds ?? [intent.commandId]);
  final String localId;
  final CommentIntent intent;
  final CommentTransportState transport;
  final CommentTask? task;
  final CommentContent? retainedContent;
  final List<String> usedCommandIds;
  final bool identityDeleted;
  final String? rejectionCode;
  CommentContent? get content =>
      identityDeleted ? null : retainedContent ?? intent.content;
  CommentJournalEntry withState(
    CommentTransportState next, {
    CommentTask? snapshot,
  }) => CommentJournalEntry(
    localId: localId,
    intent: intent,
    transport: next,
    task: snapshot ?? task,
    retainedContent: content,
    usedCommandIds: usedCommandIds,
    identityDeleted: identityDeleted,
    rejectionCode: rejectionCode,
  );
  CommentJournalEntry redactDeletedIdentity() => CommentJournalEntry(
    localId: localId,
    intent: intent.withoutContent(),
    transport: CommentTransportState.unknown,
    task: task,
    usedCommandIds: usedCommandIds,
    identityDeleted: true,
    rejectionCode: rejectionCode,
  );
  CommentJournalEntry rejected(String code) => CommentJournalEntry(
    localId: localId,
    intent: intent,
    transport: intent.operation == CommentOperation.create
        ? CommentTransportState.settled
        : CommentTransportState.unknown,
    task: task,
    retainedContent: content,
    usedCommandIds: usedCommandIds,
    identityDeleted: identityDeleted,
    rejectionCode: code,
  );
}

/// Returned only after a rejected CREATE is durably released into its open post.
class CommentRejectedInput {
  const CommentRejectedInput({required this.binding, required this.content});
  final CommentBinding binding;
  final CommentContent content;
}

/// Only the unified notifications module should render or route this value.
class CommentFailureNotice {
  const CommentFailureNotice({
    required this.localId,
    required this.task,
    required this.content,
  });
  final String localId;
  final CommentTask task;
  final CommentContent? content;
  String get taskId => task.taskId;
  String get ownerIdentityId => task.binding.identityId;
  bool get canRetry => task.canRetry;
  bool get canAbandon => task.canAbandon;
}
