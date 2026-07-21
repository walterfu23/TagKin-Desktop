import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/corrections_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

import 'fake_items_repository.dart';

/// In-memory [CorrectionsRepository] that mutates [FakeItemsRepository]
/// knowledge so [ReviewController] reconcile via `getKnowledge` works (D10).
class FakeCorrectionsRepository implements CorrectionsRepository {
  FakeCorrectionsRepository({
    required this.items,
    this.authorAccountId = 'acc_test',
  });

  final FakeItemsRepository items;
  final String authorAccountId;

  final List<({String itemId, AddTag input})> addTagCalls =
      <({String itemId, AddTag input})>[];
  final List<({String tagId, EditTag input})> editTagCalls =
      <({String tagId, EditTag input})>[];
  final List<String> removeTagCalls = <String>[];
  final List<({String itemId, CorrectCapturedAt input})> capturedAtCalls =
      <({String itemId, CorrectCapturedAt input})>[];
  final List<({String keyPeriodId, CorrectKeyPeriodBounds input})>
      boundsCalls = <({String keyPeriodId, CorrectKeyPeriodBounds input})>[];
  final List<String> undoCalls = <String>[];

  Object? addTagError;
  Object? editTagError;
  Object? removeTagError;
  Object? capturedAtError;
  Object? boundsError;
  Object? undoError;

  int _seq = 0;
  String _nextId(String prefix) => '${prefix}_${++_seq}';

  ItemKnowledge _requireKnowledge(String itemId) {
    final existing = items.peekKnowledge(itemId);
    if (existing != null) return existing;
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  Correction _correction({
    required String targetType,
    required String targetId,
    Object? previousValue,
    Object? newValue,
  }) {
    return Correction(
      id: _nextId('corr'),
      targetType: targetType,
      targetId: targetId,
      previousValue: previousValue,
      newValue: newValue,
      source: KnowledgeSource.human,
      createdAt: '2026-07-20T12:00:00.000Z',
    );
  }

  @override
  Future<TagMutationResult> addTag(String itemId, AddTag input) async {
    addTagCalls.add((itemId: itemId, input: input));
    if (addTagError != null) throw addTagError!;
    final knowledge = _requireKnowledge(itemId);
    final tag = Tag(
      id: _nextId('tag'),
      itemId: input.keyPeriodId == null ? itemId : null,
      keyPeriodId: input.keyPeriodId,
      dimension: input.dimension,
      value: input.value,
      source: KnowledgeSource.human,
      status: TagStatus.active,
      schemaVersion: 1,
      createdAt: '2026-07-20T12:00:00.000Z',
    );
    final correction = _correction(
      targetType: 'tag',
      targetId: tag.id,
      previousValue: null,
      newValue: input.value,
    );
    if (input.keyPeriodId == null) {
      items.setKnowledge(
        itemId,
        ItemKnowledge(
          item: knowledge.item,
          tags: [...knowledge.tags, tag],
          keyPeriods: knowledge.keyPeriods,
          appearances: knowledge.appearances,
          corrections: [...knowledge.corrections, correction],
        ),
      );
    } else {
      items.setKnowledge(
        itemId,
        ItemKnowledge(
          item: knowledge.item,
          tags: knowledge.tags,
          keyPeriods: [
            for (final kp in knowledge.keyPeriods)
              if (kp.id == input.keyPeriodId)
                KeyPeriodKnowledge(
                  id: kp.id,
                  itemId: kp.itemId,
                  startMs: kp.startMs,
                  endMs: kp.endMs,
                  tags: [...kp.tags, tag],
                )
              else
                kp,
          ],
          appearances: knowledge.appearances,
          corrections: [...knowledge.corrections, correction],
        ),
      );
    }
    return TagMutationResult(tag: tag, correction: correction);
  }

  @override
  Future<TagMutationResult> editTag(String tagId, EditTag input) async {
    editTagCalls.add((tagId: tagId, input: input));
    if (editTagError != null) throw editTagError!;
    // Find which item owns this tag.
    for (final item in await items.listItems()) {
      final knowledge = items.peekKnowledge(item.id);
      if (knowledge == null) continue;
      final existing = _findTag(knowledge, tagId);
      if (existing == null) continue;
      final replacement = Tag(
        id: _nextId('tag'),
        itemId: existing.itemId,
        keyPeriodId: existing.keyPeriodId,
        dimension: existing.dimension,
        value: input.value,
        source: KnowledgeSource.human,
        status: TagStatus.active,
        correctedFromTagId: existing.id,
        schemaVersion: 1,
        createdAt: '2026-07-20T12:00:00.000Z',
      );
      final correction = _correction(
        targetType: 'tag',
        targetId: replacement.id,
        previousValue: existing.value,
        newValue: input.value,
      );
      items.setKnowledge(
        item.id,
        _replaceTag(knowledge, tagId, replacement, correction),
      );
      return TagMutationResult(tag: replacement, correction: correction);
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  @override
  Future<TagMutationResult> removeTag(String tagId) async {
    removeTagCalls.add(tagId);
    if (removeTagError != null) throw removeTagError!;
    for (final item in await items.listItems()) {
      final knowledge = items.peekKnowledge(item.id);
      if (knowledge == null) continue;
      final existing = _findTag(knowledge, tagId);
      if (existing == null) continue;
      final removed = Tag(
        id: existing.id,
        itemId: existing.itemId,
        keyPeriodId: existing.keyPeriodId,
        dimension: existing.dimension,
        value: existing.value,
        source: existing.source,
        status: TagStatus.removed,
        correctedFromTagId: existing.correctedFromTagId,
        confidence: existing.confidence,
        provider: existing.provider,
        modelId: existing.modelId,
        schemaVersion: existing.schemaVersion,
        createdAt: existing.createdAt,
      );
      final correction = _correction(
        targetType: 'tag',
        targetId: tagId,
        previousValue: existing.value,
        newValue: null,
      );
      items.setKnowledge(
        item.id,
        ItemKnowledge(
          item: knowledge.item,
          tags: knowledge.tags.where((t) => t.id != tagId).toList(),
          keyPeriods: [
            for (final kp in knowledge.keyPeriods)
              KeyPeriodKnowledge(
                id: kp.id,
                itemId: kp.itemId,
                startMs: kp.startMs,
                endMs: kp.endMs,
                tags: kp.tags.where((t) => t.id != tagId).toList(),
              ),
          ],
          appearances: knowledge.appearances,
          corrections: [...knowledge.corrections, correction],
        ),
      );
      return TagMutationResult(tag: removed, correction: correction);
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  @override
  Future<CapturedAtMutationResult> correctCapturedAt(
    String itemId,
    CorrectCapturedAt input,
  ) async {
    capturedAtCalls.add((itemId: itemId, input: input));
    if (capturedAtError != null) throw capturedAtError!;
    final knowledge = _requireKnowledge(itemId);
    final prev = knowledge.item;
    final updated = Item(
      id: prev.id,
      type: prev.type,
      sourceType: prev.sourceType,
      sourceRef: prev.sourceRef,
      analysisRef: prev.analysisRef,
      analysisRefState: prev.analysisRefState,
      contentHash: prev.contentHash,
      perceptualHash: prev.perceptualHash,
      dedupOfItemId: prev.dedupOfItemId,
      capturedAt: input.capturedAt,
      processingStatus: prev.processingStatus,
      schemaVersion: prev.schemaVersion,
      createdAt: prev.createdAt,
    );
    final correction = _correction(
      targetType: 'item_captured_at',
      targetId: itemId,
      previousValue: prev.capturedAt,
      newValue: input.capturedAt,
    );
    items.setKnowledge(
      itemId,
      ItemKnowledge(
        item: updated,
        tags: knowledge.tags,
        keyPeriods: knowledge.keyPeriods,
        appearances: knowledge.appearances,
        corrections: [...knowledge.corrections, correction],
      ),
    );
    return CapturedAtMutationResult(item: updated, correction: correction);
  }

  @override
  Future<KeyPeriodMutationResult> correctKeyPeriodBounds(
    String keyPeriodId,
    CorrectKeyPeriodBounds input,
  ) async {
    boundsCalls.add((keyPeriodId: keyPeriodId, input: input));
    if (boundsError != null) throw boundsError!;
    for (final item in await items.listItems()) {
      final knowledge = items.peekKnowledge(item.id);
      if (knowledge == null) continue;
      final index = knowledge.keyPeriods.indexWhere((k) => k.id == keyPeriodId);
      if (index < 0) continue;
      final prev = knowledge.keyPeriods[index];
      final updated = KeyPeriodKnowledge(
        id: prev.id,
        itemId: prev.itemId,
        startMs: input.startMs,
        endMs: input.endMs,
        tags: prev.tags,
      );
      final correction = _correction(
        targetType: 'key_period_bounds',
        targetId: keyPeriodId,
        previousValue: {'startMs': prev.startMs, 'endMs': prev.endMs},
        newValue: {'startMs': input.startMs, 'endMs': input.endMs},
      );
      final keyPeriods = List<KeyPeriodKnowledge>.from(knowledge.keyPeriods);
      keyPeriods[index] = updated;
      items.setKnowledge(
        item.id,
        ItemKnowledge(
          item: knowledge.item,
          tags: knowledge.tags,
          keyPeriods: keyPeriods,
          appearances: knowledge.appearances,
          corrections: [...knowledge.corrections, correction],
        ),
      );
      return KeyPeriodMutationResult(
        keyPeriod: updated,
        correction: correction,
      );
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  @override
  Future<UndoCorrectionResult> undoCorrection(String correctionId) async {
    undoCalls.add(correctionId);
    if (undoError != null) throw undoError!;
    for (final item in await items.listItems()) {
      final knowledge = items.peekKnowledge(item.id);
      if (knowledge == null) continue;
      final index =
          knowledge.corrections.indexWhere((c) => c.id == correctionId);
      if (index < 0) continue;
      final correction = knowledge.corrections[index];
      // Minimal undo: drop the correction and restore previousValue when
      // target is item_captured_at or a known tag value.
      var restoredItem = knowledge.item;
      var restoredTags = knowledge.tags;
      var restoredKeyPeriods = knowledge.keyPeriods;
      String kind = 'tag';

      if (correction.targetType == 'item_captured_at') {
        kind = 'item_captured_at';
        final prev = correction.previousValue is String
            ? correction.previousValue as String
            : null;
        restoredItem = Item(
          id: knowledge.item.id,
          type: knowledge.item.type,
          sourceType: knowledge.item.sourceType,
          sourceRef: knowledge.item.sourceRef,
          analysisRef: knowledge.item.analysisRef,
          analysisRefState: knowledge.item.analysisRefState,
          contentHash: knowledge.item.contentHash,
          perceptualHash: knowledge.item.perceptualHash,
          dedupOfItemId: knowledge.item.dedupOfItemId,
          capturedAt: prev,
          processingStatus: knowledge.item.processingStatus,
          schemaVersion: knowledge.item.schemaVersion,
          createdAt: knowledge.item.createdAt,
        );
      } else if (correction.targetType == 'key_period_bounds') {
        kind = 'key_period_bounds';
        final prev = correction.previousValue;
        if (prev is Map) {
          restoredKeyPeriods = [
            for (final kp in knowledge.keyPeriods)
              if (kp.id == correction.targetId)
                KeyPeriodKnowledge(
                  id: kp.id,
                  itemId: kp.itemId,
                  startMs: (prev['startMs'] as num).toInt(),
                  endMs: (prev['endMs'] as num).toInt(),
                  tags: kp.tags,
                )
              else
                kp,
          ];
        }
      } else if (correction.previousValue is String) {
        // Restore tag value on matching active tag / re-add if removed.
        final prevValue = correction.previousValue as String;
        final found = _findTag(knowledge, correction.targetId);
        if (found != null) {
          restoredTags = [
            for (final t in knowledge.tags)
              if (t.id == found.id)
                Tag(
                  id: t.id,
                  itemId: t.itemId,
                  keyPeriodId: t.keyPeriodId,
                  dimension: t.dimension,
                  value: prevValue,
                  source: t.source,
                  status: TagStatus.active,
                  schemaVersion: t.schemaVersion,
                  createdAt: t.createdAt,
                )
              else
                t,
          ];
        } else if (correction.newValue == null) {
          // Undo of a remove — re-add a tag with previous value.
          restoredTags = [
            ...knowledge.tags,
            Tag(
              id: correction.targetId,
              itemId: item.id,
              dimension: 'what',
              value: prevValue,
              source: KnowledgeSource.model,
              status: TagStatus.active,
              schemaVersion: 1,
              createdAt: '2026-07-20T00:00:00.000Z',
            ),
          ];
        }
      }

      final remaining = List<Correction>.from(knowledge.corrections)
        ..removeAt(index);
      items.setKnowledge(
        item.id,
        ItemKnowledge(
          item: restoredItem,
          tags: restoredTags,
          keyPeriods: restoredKeyPeriods,
          appearances: knowledge.appearances,
          corrections: remaining,
        ),
      );
      return UndoCorrectionResult(
        correction: correction,
        restored: UndoCorrectionResultRestored(
          kind: kind,
          item: kind == 'item_captured_at' ? restoredItem : null,
          tag: kind == 'tag' && restoredTags.isNotEmpty
              ? restoredTags.last
              : null,
          keyPeriod: kind == 'key_period_bounds' &&
                  restoredKeyPeriods.isNotEmpty
              ? restoredKeyPeriods.firstWhere(
                  (k) => k.id == correction.targetId,
                  orElse: () => restoredKeyPeriods.first,
                )
              : null,
        ),
      );
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  Tag? _findTag(ItemKnowledge knowledge, String tagId) {
    for (final t in knowledge.tags) {
      if (t.id == tagId) return t;
    }
    for (final kp in knowledge.keyPeriods) {
      for (final t in kp.tags) {
        if (t.id == tagId) return t;
      }
    }
    return null;
  }

  ItemKnowledge _replaceTag(
    ItemKnowledge knowledge,
    String oldTagId,
    Tag replacement,
    Correction correction,
  ) {
    return ItemKnowledge(
      item: knowledge.item,
      tags: [
        for (final t in knowledge.tags)
          if (t.id == oldTagId) replacement else t,
      ],
      keyPeriods: [
        for (final kp in knowledge.keyPeriods)
          KeyPeriodKnowledge(
            id: kp.id,
            itemId: kp.itemId,
            startMs: kp.startMs,
            endMs: kp.endMs,
            tags: [
              for (final t in kp.tags)
                if (t.id == oldTagId) replacement else t,
            ],
          ),
      ],
      appearances: knowledge.appearances,
      corrections: [...knowledge.corrections, correction],
    );
  }
}

/// Fixture [Correction] for D10 tests.
Correction fixtureCorrection({
  String id = 'corr_1',
  String targetType = 'tag',
  String targetId = 'tag_1',
  Object? previousValue = 'old',
  Object? newValue = 'new',
}) {
  return Correction(
    id: id,
    targetType: targetType,
    targetId: targetId,
    previousValue: previousValue,
    newValue: newValue,
    source: KnowledgeSource.human,
    createdAt: '2026-07-20T12:00:00.000Z',
  );
}
