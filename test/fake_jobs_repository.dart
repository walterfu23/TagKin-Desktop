import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

import 'fake_items_repository.dart';

/// In-memory [JobsRepository] for widget/integration tests (no network).
class FakeJobsRepository implements JobsRepository {
  FakeJobsRepository({
    this.itemId = 'item_1',
    Item? item,
    List<Job>? jobs,
    LibraryExport? export,
    this.analyzeError,
    this.jobsError,
    this.cancelError,
    this.deleteError,
    this.exportError,
    this.analyzeDelay,
    this.onDelete,
  })  : item = item ?? fixtureItem(id: itemId),
        _jobs = List<Job>.from(jobs ?? const []),
        export = export ?? fixtureLibraryExport();

  String itemId;
  Item item;
  final List<Job> _jobs;
  LibraryExport export;

  final Object? analyzeError;
  final Object? jobsError;
  final Object? cancelError;
  final Object? deleteError;
  final Object? exportError;

  /// Optional delay before [analyzeItem] completes (tests race/cancel).
  final Duration? analyzeDelay;

  /// Optional delay before [listItemJobs] completes (tests stale-refresh race).
  Duration? listJobsDelay;

  /// Invoked after a successful [deleteItem] (e.g. to update [FakeItemsRepository]).
  final void Function(String itemId)? onDelete;

  /// Ordered job lists consumed on each [listItemJobs] call (FIFO).
  /// When empty, returns [_jobs].
  final List<List<Job>> jobsSequence = <List<Job>>[];

  int analyzeCallCount = 0;
  int listJobsCallCount = 0;
  int cancelCallCount = 0;
  int deleteCallCount = 0;
  int exportCallCount = 0;

  final List<String> analyzedItemIds = <String>[];
  final List<String> deletedItemIds = <String>[];

  void setJobs(List<Job> jobs) {
    _jobs
      ..clear()
      ..addAll(jobs);
  }

  @override
  Future<AnalyzeResultResponse> analyzeItem(String id) async {
    analyzeCallCount++;
    analyzedItemIds.add(id);
    if (analyzeDelay != null) {
      await Future<void>.delayed(analyzeDelay!);
    }
    if (analyzeError != null) throw analyzeError!;
    if (id != itemId) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final tagged = Item(
      id: item.id,
      type: item.type,
      sourceType: item.sourceType,
      sourceRef: item.sourceRef,
      analysisRef: item.analysisRef,
      analysisRefState: item.analysisRefState,
      contentHash: item.contentHash,
      perceptualHash: item.perceptualHash,
      dedupOfItemId: item.dedupOfItemId,
      capturedAt: item.capturedAt,
      processingStatus: ProcessingStatus.tagged,
      schemaVersion: item.schemaVersion,
      createdAt: item.createdAt,
    );
    item = tagged;
    final job = fixtureJob(
      id: 'job_analyze_$analyzeCallCount',
      itemId: id,
      state: JobState.completed,
    );
    _jobs.insert(0, job);
    return AnalyzeResultResponse(
      item: tagged,
      tagIds: const ['tag_1'],
      provider: 'stub',
      modelId: 'stub-model',
      escalated: false,
    );
  }

  @override
  Future<List<Job>> listItemJobs(String id) async {
    listJobsCallCount++;
    if (listJobsDelay != null) {
      await Future<void>.delayed(listJobsDelay!);
    }
    if (jobsError != null) throw jobsError!;
    if (id != itemId) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    if (jobsSequence.isNotEmpty) {
      return List<Job>.from(jobsSequence.removeAt(0));
    }
    return List<Job>.from(_jobs);
  }

  @override
  Future<CancelItemResponse> cancelItem(String id) async {
    cancelCallCount++;
    if (cancelError != null) throw cancelError!;
    if (id != itemId) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final cancelledItem = Item(
      id: item.id,
      type: item.type,
      sourceType: item.sourceType,
      sourceRef: item.sourceRef,
      analysisRef: item.analysisRef,
      analysisRefState: item.analysisRefState,
      contentHash: item.contentHash,
      perceptualHash: item.perceptualHash,
      dedupOfItemId: item.dedupOfItemId,
      capturedAt: item.capturedAt,
      processingStatus: ProcessingStatus.cancelled,
      schemaVersion: item.schemaVersion,
      createdAt: item.createdAt,
    );
    item = cancelledItem;
    final job = fixtureJob(
      id: 'job_cancel_$cancelCallCount',
      itemId: id,
      state: JobState.cancelled,
    );
    _jobs.insert(0, job);
    return CancelItemResponse(item: cancelledItem, job: job);
  }

  @override
  Future<void> deleteItem(String id) async {
    deleteCallCount++;
    deletedItemIds.add(id);
    if (deleteError != null) throw deleteError!;
    if (id != itemId) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    onDelete?.call(id);
  }

  @override
  Future<LibraryExport> exportLibrary() async {
    exportCallCount++;
    if (exportError != null) throw exportError!;
    return export;
  }
}

Job fixtureJob({
  String id = 'job_1',
  String? itemId = 'item_1',
  JobState state = JobState.queued,
  JobKind kind = JobKind.analyze,
  int attempts = 0,
}) {
  return Job(
    id: id,
    itemId: itemId,
    kind: kind,
    state: state,
    attempts: attempts,
    pipelineVersion: 1,
    createdAt: '2026-07-20T00:00:00.000Z',
    updatedAt: '2026-07-20T00:00:00.000Z',
  );
}

LibraryExport fixtureLibraryExport({
  List<Item>? items,
  String exportedAt = '2026-07-20T12:00:00.000Z',
}) {
  return LibraryExport(
    items: items ?? [fixtureItem()],
    tags: const [],
    persons: const [],
    comments: const [],
    corrections: const [],
    exportedAt: exportedAt,
  );
}
