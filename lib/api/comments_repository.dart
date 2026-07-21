import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Typed client for item / key-period comments (D10 / S9).
///
/// Private text comments only — never media bytes (R1). Author is stamped
/// server-side from the token; never send `authorUserId` / `ownerUserId` (R10).
class CommentsRepository {
  CommentsRepository(this._client);

  final ApiClient _client;

  /// `GET /items/{itemId}/comments` — active comments for the item (incl.
  /// key-period-level comments on that item).
  Future<List<Comment>> listItemComments(String itemId) async {
    final response = await _client.get('/items/$itemId/comments');
    final json = jsonDecode(response.body);
    if (json is! List<dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /items/{id}/comments response shape',
      );
    }
    return json
        .map((e) => Comment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /items/{itemId}/comments` — create item-level comment.
  Future<Comment> createItemComment(
    String itemId,
    CreateComment input,
  ) async {
    final response = await _client.post(
      '/items/$itemId/comments',
      body: input.toJson(),
    );
    return _comment(response, 'create-item-comment');
  }

  /// `POST /key-periods/{keyPeriodId}/comments` — create key-period comment.
  ///
  /// `itemId` is derived server-side; never accepted from the body (R10).
  Future<Comment> createKeyPeriodComment(
    String keyPeriodId,
    CreateComment input,
  ) async {
    final response = await _client.post(
      '/key-periods/$keyPeriodId/comments',
      body: input.toJson(),
    );
    return _comment(response, 'create-key-period-comment');
  }

  /// `PATCH /comments/{commentId}` — edit body of an owned active comment.
  Future<Comment> editComment(String commentId, EditComment input) async {
    final response = await _client.patch(
      '/comments/$commentId',
      body: input.toJson(),
    );
    return _comment(response, 'edit-comment');
  }

  /// `DELETE /comments/{commentId}` — soft-delete (sets deletedAt).
  Future<Comment> deleteComment(String commentId) async {
    final response = await _client.delete('/comments/$commentId');
    return _comment(response, 'delete-comment');
  }

  Comment _comment(http.Response response, String label) {
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected $label response shape',
      );
    }
    return Comment.fromJson(json);
  }
}
