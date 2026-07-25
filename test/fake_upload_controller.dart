import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

import 'fake_items_repository.dart';

/// Test double for item-detail re-upload / re-analyze chains.
class FakeUploadController extends UploadController {
  FakeUploadController({
    FakeItemsRepository? items,
    this.succeed = true,
    this.errorToReturn,
  }) : super(itemsRepository: items ?? FakeItemsRepository(items: []));

  int uploadCallCount = 0;
  bool succeed;
  Object? errorToReturn;
  Item? lastItem;

  @override
  Future<UploadOutcome> uploadItemFromLocal(
    Item item, {
    Future<LocalMediaResolution> Function(Item item)? resolveMedia,
  }) async {
    uploadCallCount += 1;
    lastItem = item;
    phase = UploadPhase.running;
    notifyListeners();
    if (!succeed) {
      final err = errorToReturn ?? StateError('fake upload failed');
      final outcome = UploadOutcome(itemId: item.id, error: err);
      outcomes = [outcome];
      phase = UploadPhase.error;
      error = err;
      notifyListeners();
      return outcome;
    }
    final updated = Item(
      id: item.id,
      type: item.type,
      sourceType: item.sourceType,
      sourceRef: item.sourceRef,
      analysisRef: 'files/fake-reupload-${item.id}',
      analysisRefState: AnalysisRefState.ready,
      contentHash: item.contentHash,
      capturedAt: item.capturedAt,
      processingStatus: item.processingStatus,
      schemaVersion: item.schemaVersion,
      createdAt: item.createdAt,
    );
    final outcome = UploadOutcome(
      itemId: item.id,
      analysisRef: updated.analysisRef,
      item: updated,
    );
    outcomes = [outcome];
    phase = UploadPhase.done;
    notifyListeners();
    return outcome;
  }
}
