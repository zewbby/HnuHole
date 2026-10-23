import 'post_api.dart';
import 'post_models.dart';

/// Private account archives, independent of speaking identity.
abstract interface class PersonalCollectionsApi {
  Future<PostResponse<PostsPage<PostCard>>> personalCollection({
    required String sessionToken,
    required bool favorites,
    String? cursor,
    int limit = 20,
  });
}
