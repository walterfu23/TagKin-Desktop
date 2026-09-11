import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Typed client for S12 item-list filter (`POST /item-lists`, facets).
///
/// Metadata only — never media bytes (R1). Owner is derived server-side from
/// the bearer token; this client never sends a client-supplied owner field
/// (R10). Filter matching stays on the server (R8 / §4).
class ItemListsRepository {
  ItemListsRepository(this._client);

  final ApiClient _client;

  /// `GET /item-lists/facets` — distinct who/what/where picker values.
  Future<ItemListFacets> listFacets() async {
    final response = await _client.get('/item-lists/facets');
    return ItemListFacets.fromJson(
      _client.decodeMap(response, '/item-lists/facets'),
    );
  }

  /// `POST /item-lists` — server-side filter, dedup, and when-sort.
  Future<ItemList> createItemList(ItemListFilter filter) async {
    final response = await _client.post(
      '/item-lists',
      body: filter.toJson(),
    );
    return ItemList.fromJson(_client.decodeMap(response, '/item-lists'));
  }
}
