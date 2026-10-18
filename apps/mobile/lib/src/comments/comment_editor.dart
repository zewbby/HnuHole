import '../posts/post_protocol.dart';
import 'comment_models.dart';

class CommentTarget {
  CommentTarget({required this.postId, this.rootCommentId, this.commentId}) {
    PostProtocol.resourceId(postId);
    if ((rootCommentId == null) != (commentId == null)) {
      throw const FormatException('Invalid reply target');
    }
    if (rootCommentId != null) PostProtocol.resourceId(rootCommentId!);
    if (commentId != null) PostProtocol.resourceId(commentId!);
  }
  final String postId;
  final String? rootCommentId, commentId;
  bool sameAs(CommentTarget other) =>
      postId == other.postId &&
      rootCommentId == other.rootCommentId &&
      commentId == other.commentId;
}

/// Unsubmitted input lives only for this open post. Never journal this editor.
class CommentEditor {
  CommentEditor(this._target);
  CommentTarget _target;
  CommentTarget get target => _target;
  String _body = '';
  CommentImage? _image;
  String get body => _body;
  set body(String value) {
    if (_left) throw StateError('The post was left');
    _body = value;
  }

  CommentImage? get image => _image;
  bool imageFailed = false;
  bool open = true;
  bool _left = false;
  int _targetVersion = 0;

  bool get hasInput => body.isNotEmpty || image != null;
  bool get active => !_left;
  void collapse() => open = false;
  void expand() {
    if (_left) throw StateError('The post was left');
    open = true;
  }

  void setImage(CommentImage? value) {
    if (_left) throw StateError('The post was left');
    _image = value;
    imageFailed = false;
  }

  Future<bool> switchTarget(
    CommentTarget next, {
    required Future<bool> Function(CommentTarget next) confirm,
  }) async {
    if (_left || target.postId != next.postId) return false;
    final version = ++_targetVersion;
    if (target.sameAs(next)) return true;
    if (hasInput && !await confirm(next)) return false;
    if (_left || version != _targetVersion) return false;
    _target = next;
    return true;
  }

  CommentContent content() {
    if (_left || imageFailed) throw StateError('Input is unavailable');
    return CommentContent(body: body, image: image);
  }

  void leave() {
    _left = true;
    _targetVersion++;
    _body = '';
    _image = null;
    imageFailed = false;
    _target = CommentTarget(postId: target.postId);
    open = false;
  }
}
