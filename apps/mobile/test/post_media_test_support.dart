const mediaPostId = '11111111-1111-4111-8111-111111111111';
const mediaOtherId = '22222222-2222-4222-8222-222222222222';
Map<String, Object?> mediaManifest({
  int count = 1,
  int bytes = 8,
  String mime = 'image/png',
  int frames = 1,
  int width = 3,
  int height = 2,
  DateTime? at,
  Duration lifetime = const Duration(seconds: 60),
}) => {
  'postId': mediaPostId,
  'accessValidUntil': (at ?? DateTime.utc(2026, 10, 8))
      .add(lifetime)
      .toIso8601String(),
  'images': [
    for (var i = 0; i < count; i++)
      {
        'mediaId':
            '33333333-3333-4333-8333-${(i + 1).toString().padLeft(12, '0')}',
        'contentVersionId':
            '44444444-4444-4444-8444-${(i + 1).toString().padLeft(12, '0')}',
        'position': i,
        'width': width,
        'height': height,
        'pixelWidth': width,
        'pixelHeight': height,
        'frames': frames,
        'animated': frames > 1,
        'saveAllowed': true,
        for (final source in ['thumbnail', 'full', 'original'])
          source: {
            'path':
                '/api/v1/posts/$mediaPostId/images/44444444-4444-4444-8444-${(i + 1).toString().padLeft(12, '0')}/original',
            'mimeType': mime,
            'byteLength': bytes,
          },
      },
  ],
};
