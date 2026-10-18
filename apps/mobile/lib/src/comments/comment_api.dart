import 'comment_models.dart';

/// The host supplies current authenticated transport; tokens never enter models.
abstract interface class CommentApi {
  /// The adapter must resolve the command receipt and read the current task.
  /// A historical ACCEPTED receipt by itself is never a task snapshot.
  Future<CommentTask> execute(CommentIntent intent);

  /// Query the original command and its fixed task ID.
  /// A null result is unknown, never permission to resend automatically.
  Future<CommentTask?> query(CommentIntent intent);

  /// Read latest task state after the original mutation was authoritatively
  /// rejected. This must not substitute a cached pre-mutation FAILED snapshot.
  Future<CommentTask?> queryTask({
    required String taskId,
    required CommentBinding binding,
  });
}

/// Only a checked REJECTED/NOT_ACCEPTED receipt for the original command key may
/// produce this value. HTTP status codes, timeouts and absence are not receipts.
class CommentCommandRejected implements Exception {
  CommentCommandRejected(this.code) {
    if (!RegExp(r'^[A-Z][A-Z0-9_]{0,63}$').hasMatch(code)) {
      throw const FormatException('Invalid authoritative rejection code');
    }
  }
  final String code;
}

/// Authoritative confirmation that this command/task did not publish because
/// its identity was deleted. An identity-deletion event alone is insufficient:
/// unknown tasks must first query their original result.
class CommentIdentityDeleted implements Exception {
  const CommentIdentityDeleted();
}

/// A host implementation must durably and atomically save the intent plus any
/// referenced original image bytes before put completes. This is a task journal,
/// not a comment draft list. Entries and blobs must be isolated by account.
abstract interface class CommentJournal {
  Future<List<CommentJournalEntry>> read(String accountId);
  Future<void> put(String accountId, CommentJournalEntry entry);
  Future<void> remove(String accountId, String localId);
}
