import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// In-memory [CommentsRepository] for D10 tests.
class FakeCommentsRepository implements CommentsRepository {
  FakeCommentsRepository({
    List<Comment>? comments,
    this.authorUserId = 'acc_test',
  }) : _comments = List<Comment>.from(comments ?? const []);

  final List<Comment> _comments;
  final String authorUserId;

  final List<({String itemId, CreateComment input})> createItemCalls =
      <({String itemId, CreateComment input})>[];
  final List<({String keyPeriodId, CreateComment input})> createKpCalls =
      <({String keyPeriodId, CreateComment input})>[];
  final List<({String commentId, EditComment input})> editCalls =
      <({String commentId, EditComment input})>[];
  final List<String> deleteCalls = <String>[];

  Object? listError;
  Object? createError;
  Object? editError;
  Object? deleteError;

  int _seq = 0;

  @override
  Future<List<Comment>> listItemComments(String itemId) async {
    if (listError != null) throw listError!;
    return _comments
        .where(
          (c) =>
              c.itemId == itemId &&
              c.deletedAt == null,
        )
        .toList();
  }

  @override
  Future<Comment> createItemComment(
    String itemId,
    CreateComment input,
  ) async {
    createItemCalls.add((itemId: itemId, input: input));
    if (createError != null) throw createError!;
    // Body must not carry author/owner (R10) — fake stamps from session.
    final comment = Comment(
      id: 'comment_${++_seq}',
      itemId: itemId,
      authorUserId: authorUserId,
      body: input.body,
      createdAt: '2026-07-20T12:00:00.000Z',
    );
    _comments.add(comment);
    return comment;
  }

  @override
  Future<Comment> createKeyPeriodComment(
    String keyPeriodId,
    CreateComment input,
  ) async {
    createKpCalls.add((keyPeriodId: keyPeriodId, input: input));
    if (createError != null) throw createError!;
    final comment = Comment(
      id: 'comment_${++_seq}',
      itemId: 'item_derived',
      keyPeriodId: keyPeriodId,
      authorUserId: authorUserId,
      body: input.body,
      createdAt: '2026-07-20T12:00:00.000Z',
    );
    _comments.add(comment);
    return comment;
  }

  @override
  Future<Comment> editComment(String commentId, EditComment input) async {
    editCalls.add((commentId: commentId, input: input));
    if (editError != null) throw editError!;
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final prev = _comments[index];
    if (prev.deletedAt != null) {
      throw ApiException(statusCode: 400, message: 'Deleted');
    }
    final updated = Comment(
      id: prev.id,
      itemId: prev.itemId,
      keyPeriodId: prev.keyPeriodId,
      authorUserId: prev.authorUserId,
      body: input.body,
      deletedAt: prev.deletedAt,
      createdAt: prev.createdAt,
      updatedAt: '2026-07-20T13:00:00.000Z',
    );
    _comments[index] = updated;
    return updated;
  }

  @override
  Future<Comment> deleteComment(String commentId) async {
    deleteCalls.add(commentId);
    if (deleteError != null) throw deleteError!;
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final prev = _comments[index];
    final updated = Comment(
      id: prev.id,
      itemId: prev.itemId,
      keyPeriodId: prev.keyPeriodId,
      authorUserId: prev.authorUserId,
      body: prev.body,
      deletedAt: '2026-07-20T14:00:00.000Z',
      createdAt: prev.createdAt,
      updatedAt: prev.updatedAt,
    );
    _comments[index] = updated;
    return updated;
  }
}

/// Fixture [Comment] for D10 tests.
Comment fixtureComment({
  String id = 'comment_1',
  String? itemId = 'item_1',
  String? keyPeriodId,
  String authorUserId = 'acc_test',
  String body = 'hello',
}) {
  return Comment(
    id: id,
    itemId: itemId,
    keyPeriodId: keyPeriodId,
    authorUserId: authorUserId,
    body: body,
    createdAt: '2026-07-20T12:00:00.000Z',
  );
}
