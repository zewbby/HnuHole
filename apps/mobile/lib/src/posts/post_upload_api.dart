import 'dart:typed_data';

import 'post_api.dart';
import 'post_models.dart';
import 'post_upload_models.dart';

abstract interface class PostUploadApi {
  Future<PostResponse<PostCommandResult>> createWithImages({
    required String sessionToken,
    required String commandId,
    required String channelId,
    required String identityId,
    required String title,
    required String body,
    required List<PostImageSelection> images,
  });
  Future<PostResponse<PostCommandResult>> retryWithImages({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
    required String title,
    required String body,
    required List<PostImageSelection> images,
  });
  Future<PostResponse<PostUploadState>> uploads({
    required String sessionToken,
    required String taskId,
    required int version,
  });
  Future<PostResponse<PostUploadGrant>> uploadGrant({
    required String sessionToken,
    required String taskId,
    required int version,
    required String mediaId,
  });
  Future<DateTime> putOriginal({
    required String uploadToken,
    required String taskId,
    required int version,
    required PostImageSelection image,
    required Uint8List bytes,
  });
}
