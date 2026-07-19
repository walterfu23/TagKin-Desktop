// GENERATED — do not edit by hand.
// Regenerate via tool/gen_contract.dart (mac/102_codegen.sh · win/102_codegen.ps1).
// Single source of truth: @tagkin/contract OpenAPI (R2).
// ignore_for_file: type=lint

class Account {
  const Account({
    required this.id,
    this.email,
    required this.createdAt,
  });

  final String id;
  final String? email;
  final String createdAt;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        email: json['email'] == null ? null : json['email'] as String,
        createdAt: json['createdAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'email': email,
        'createdAt': createdAt,
      };
}

class AddTag {
  const AddTag({
    required this.dimension,
    required this.value,
    this.keyPeriodId,
  });

  final String dimension;
  final String value;
  final String? keyPeriodId;

  factory AddTag.fromJson(Map<String, dynamic> json) => AddTag(
        dimension: json['dimension'] as String,
        value: json['value'] as String,
        keyPeriodId: json['keyPeriodId'] == null ? null : json['keyPeriodId'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dimension': dimension,
        'value': value,
        'keyPeriodId': keyPeriodId,
      };
}

enum AnalysisRefState {
  pending('pending'),
  ready('ready'),
  expired('expired'),
  deleted('deleted'),
  unavailable('unavailable');

  const AnalysisRefState(this.wire);

  final String wire;

  static AnalysisRefState fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

class AnalyzeResultResponse {
  const AnalyzeResultResponse({
    required this.item,
    required this.tagIds,
    required this.provider,
    required this.modelId,
    required this.escalated,
  });

  final Item item;
  final List<String> tagIds;
  final String provider;
  final String modelId;
  final bool escalated;

  factory AnalyzeResultResponse.fromJson(Map<String, dynamic> json) => AnalyzeResultResponse(
        item: Item.fromJson(json['item'] as Map<String, dynamic>),
        tagIds: (json['tagIds'] as List<dynamic>).map((e) => e as String).toList(),
        provider: json['provider'] as String,
        modelId: json['modelId'] as String,
        escalated: json['escalated'] as bool,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item': item.toJson(),
        'tagIds': tagIds.map((e) => e).toList(),
        'provider': provider,
        'modelId': modelId,
        'escalated': escalated,
      };
}

class CancelItemResponse {
  const CancelItemResponse({
    required this.item,
    this.job,
  });

  final Item item;
  final Job? job;

  factory CancelItemResponse.fromJson(Map<String, dynamic> json) => CancelItemResponse(
        item: Item.fromJson(json['item'] as Map<String, dynamic>),
        job: json['job'] == null ? null : Job.fromJson(json['job'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item': item.toJson(),
        'job': job?.toJson(),
      };
}

class CapturedAtMutationResult {
  const CapturedAtMutationResult({
    required this.item,
    required this.correction,
  });

  final Item item;
  final Correction correction;

  factory CapturedAtMutationResult.fromJson(Map<String, dynamic> json) => CapturedAtMutationResult(
        item: Item.fromJson(json['item'] as Map<String, dynamic>),
        correction: Correction.fromJson(json['correction'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item': item.toJson(),
        'correction': correction.toJson(),
      };
}

class Comment {
  const Comment({
    required this.id,
    this.itemId,
    this.keyPeriodId,
    required this.authorUserId,
    required this.body,
    this.deletedAt,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? itemId;
  final String? keyPeriodId;
  final String authorUserId;
  final String body;
  final String? deletedAt;
  final String createdAt;
  final String? updatedAt;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String,
        itemId: json['itemId'] == null ? null : json['itemId'] as String,
        keyPeriodId: json['keyPeriodId'] == null ? null : json['keyPeriodId'] as String,
        authorUserId: json['authorUserId'] as String,
        body: json['body'] as String,
        deletedAt: json['deletedAt'] == null ? null : json['deletedAt'] as String,
        createdAt: json['createdAt'] as String,
        updatedAt: json['updatedAt'] == null ? null : json['updatedAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'itemId': itemId,
        'keyPeriodId': keyPeriodId,
        'authorUserId': authorUserId,
        'body': body,
        'deletedAt': deletedAt,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class CorrectCapturedAt {
  const CorrectCapturedAt({
    this.capturedAt,
  });

  final String? capturedAt;

  factory CorrectCapturedAt.fromJson(Map<String, dynamic> json) => CorrectCapturedAt(
        capturedAt: json['capturedAt'] == null ? null : json['capturedAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'capturedAt': capturedAt,
      };
}

class CorrectKeyPeriodBounds {
  const CorrectKeyPeriodBounds({
    required this.startMs,
    required this.endMs,
  });

  final int startMs;
  final int endMs;

  factory CorrectKeyPeriodBounds.fromJson(Map<String, dynamic> json) => CorrectKeyPeriodBounds(
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'startMs': startMs,
        'endMs': endMs,
      };
}

class Correction {
  const Correction({
    required this.id,
    required this.targetType,
    required this.targetId,
    this.previousValue,
    this.newValue,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String targetType;
  final String targetId;
  final Object? previousValue;
  final Object? newValue;
  final KnowledgeSource source;
  final String createdAt;

  factory Correction.fromJson(Map<String, dynamic> json) => Correction(
        id: json['id'] as String,
        targetType: json['targetType'] as String,
        targetId: json['targetId'] as String,
        previousValue: json['previousValue'] == null ? null : json['previousValue'],
        newValue: json['newValue'] == null ? null : json['newValue'],
        source: KnowledgeSource.fromWire(json['source'] as String),
        createdAt: json['createdAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'targetType': targetType,
        'targetId': targetId,
        'previousValue': previousValue,
        'newValue': newValue,
        'source': source.wire,
        'createdAt': createdAt,
      };
}

class CreateComment {
  const CreateComment({
    required this.body,
  });

  final String body;

  factory CreateComment.fromJson(Map<String, dynamic> json) => CreateComment(
        body: json['body'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'body': body,
      };
}

class CreateItem {
  const CreateItem({
    required this.type,
    required this.sourceType,
    this.sourceRef,
    this.contentHash,
    this.capturedAt,
  });

  final ItemType type;
  final SourceType sourceType;
  final String? sourceRef;
  final String? contentHash;
  final String? capturedAt;

  factory CreateItem.fromJson(Map<String, dynamic> json) => CreateItem(
        type: ItemType.fromWire(json['type'] as String),
        sourceType: SourceType.fromWire(json['sourceType'] as String),
        sourceRef: json['sourceRef'] == null ? null : json['sourceRef'] as String,
        contentHash: json['contentHash'] == null ? null : json['contentHash'] as String,
        capturedAt: json['capturedAt'] == null ? null : json['capturedAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.wire,
        'sourceType': sourceType.wire,
        'sourceRef': sourceRef,
        'contentHash': contentHash,
        'capturedAt': capturedAt,
      };
}

class CreateUploadGrant {
  const CreateUploadGrant({
    required this.mimeType,
  });

  final String mimeType;

  factory CreateUploadGrant.fromJson(Map<String, dynamic> json) => CreateUploadGrant(
        mimeType: json['mimeType'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mimeType': mimeType,
      };
}

class EditComment {
  const EditComment({
    required this.body,
  });

  final String body;

  factory EditComment.fromJson(Map<String, dynamic> json) => EditComment(
        body: json['body'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'body': body,
      };
}

class EditTag {
  const EditTag({
    required this.value,
  });

  final String value;

  factory EditTag.fromJson(Map<String, dynamic> json) => EditTag(
        value: json['value'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'value': value,
      };
}

class Error {
  const Error({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  factory Error.fromJson(Map<String, dynamic> json) => Error(
        code: json['code'] as String,
        message: json['message'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'message': message,
      };
}

class Health {
  const Health({
    required this.status,
    this.version,
  });

  final String status;
  final String? version;

  factory Health.fromJson(Map<String, dynamic> json) => Health(
        status: json['status'] as String,
        version: json['version'] == null ? null : json['version'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status,
        'version': version,
      };
}

class Item {
  const Item({
    required this.id,
    required this.type,
    required this.sourceType,
    this.sourceRef,
    this.analysisRef,
    required this.analysisRefState,
    this.contentHash,
    this.perceptualHash,
    this.dedupOfItemId,
    this.capturedAt,
    required this.processingStatus,
    required this.schemaVersion,
    required this.createdAt,
  });

  final String id;
  final ItemType type;
  final SourceType sourceType;
  final String? sourceRef;
  final String? analysisRef;
  final AnalysisRefState analysisRefState;
  final String? contentHash;
  final String? perceptualHash;
  final String? dedupOfItemId;
  final String? capturedAt;
  final ProcessingStatus processingStatus;
  final int schemaVersion;
  final String createdAt;

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String,
        type: ItemType.fromWire(json['type'] as String),
        sourceType: SourceType.fromWire(json['sourceType'] as String),
        sourceRef: json['sourceRef'] == null ? null : json['sourceRef'] as String,
        analysisRef: json['analysisRef'] == null ? null : json['analysisRef'] as String,
        analysisRefState: AnalysisRefState.fromWire(json['analysisRefState'] as String),
        contentHash: json['contentHash'] == null ? null : json['contentHash'] as String,
        perceptualHash: json['perceptualHash'] == null ? null : json['perceptualHash'] as String,
        dedupOfItemId: json['dedupOfItemId'] == null ? null : json['dedupOfItemId'] as String,
        capturedAt: json['capturedAt'] == null ? null : json['capturedAt'] as String,
        processingStatus: ProcessingStatus.fromWire(json['processingStatus'] as String),
        schemaVersion: (json['schemaVersion'] as num).toInt(),
        createdAt: json['createdAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.wire,
        'sourceType': sourceType.wire,
        'sourceRef': sourceRef,
        'analysisRef': analysisRef,
        'analysisRefState': analysisRefState.wire,
        'contentHash': contentHash,
        'perceptualHash': perceptualHash,
        'dedupOfItemId': dedupOfItemId,
        'capturedAt': capturedAt,
        'processingStatus': processingStatus.wire,
        'schemaVersion': schemaVersion,
        'createdAt': createdAt,
      };
}

class ItemKnowledge {
  const ItemKnowledge({
    required this.item,
    required this.tags,
    required this.keyPeriods,
    required this.appearances,
    required this.corrections,
  });

  final Item item;
  final List<Tag> tags;
  final List<KeyPeriodKnowledge> keyPeriods;
  final List<PersonAppearance> appearances;
  final List<Correction> corrections;

  factory ItemKnowledge.fromJson(Map<String, dynamic> json) => ItemKnowledge(
        item: Item.fromJson(json['item'] as Map<String, dynamic>),
        tags: (json['tags'] as List<dynamic>).map((e) => Tag.fromJson(e as Map<String, dynamic>)).toList(),
        keyPeriods: (json['keyPeriods'] as List<dynamic>).map((e) => KeyPeriodKnowledge.fromJson(e as Map<String, dynamic>)).toList(),
        appearances: (json['appearances'] as List<dynamic>).map((e) => PersonAppearance.fromJson(e as Map<String, dynamic>)).toList(),
        corrections: (json['corrections'] as List<dynamic>).map((e) => Correction.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item': item.toJson(),
        'tags': tags.map((e) => e.toJson()).toList(),
        'keyPeriods': keyPeriods.map((e) => e.toJson()).toList(),
        'appearances': appearances.map((e) => e.toJson()).toList(),
        'corrections': corrections.map((e) => e.toJson()).toList(),
      };
}

enum ItemType {
  photo('photo'),
  video('video');

  const ItemType(this.wire);

  final String wire;

  static ItemType fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

class Job {
  const Job({
    required this.id,
    this.itemId,
    required this.kind,
    required this.state,
    required this.attempts,
    required this.pipelineVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? itemId;
  final JobKind kind;
  final JobState state;
  final int attempts;
  final int pipelineVersion;
  final String createdAt;
  final String updatedAt;

  factory Job.fromJson(Map<String, dynamic> json) => Job(
        id: json['id'] as String,
        itemId: json['itemId'] == null ? null : json['itemId'] as String,
        kind: JobKind.fromWire(json['kind'] as String),
        state: JobState.fromWire(json['state'] as String),
        attempts: (json['attempts'] as num).toInt(),
        pipelineVersion: (json['pipelineVersion'] as num).toInt(),
        createdAt: json['createdAt'] as String,
        updatedAt: json['updatedAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'itemId': itemId,
        'kind': kind.wire,
        'state': state.wire,
        'attempts': attempts,
        'pipelineVersion': pipelineVersion,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

enum JobKind {
  analyze('analyze');

  const JobKind(this.wire);

  final String wire;

  static JobKind fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

enum JobState {
  queued('queued'),
  awaitingModelAccess('awaiting_model_access'),
  reserved('reserved'),
  processing('processing'),
  pausedForBudget('paused_for_budget'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const JobState(this.wire);

  final String wire;

  static JobState fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

class KeyPeriod {
  const KeyPeriod({
    required this.id,
    required this.itemId,
    required this.startMs,
    required this.endMs,
  });

  final String id;
  final String itemId;
  final int startMs;
  final int endMs;

  factory KeyPeriod.fromJson(Map<String, dynamic> json) => KeyPeriod(
        id: json['id'] as String,
        itemId: json['itemId'] as String,
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'itemId': itemId,
        'startMs': startMs,
        'endMs': endMs,
      };
}

class KeyPeriodKnowledge {
  const KeyPeriodKnowledge({
    required this.id,
    required this.itemId,
    required this.startMs,
    required this.endMs,
    required this.tags,
  });

  final String id;
  final String itemId;
  final int startMs;
  final int endMs;
  final List<Tag> tags;

  factory KeyPeriodKnowledge.fromJson(Map<String, dynamic> json) => KeyPeriodKnowledge(
        id: json['id'] as String,
        itemId: json['itemId'] as String,
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
        tags: (json['tags'] as List<dynamic>).map((e) => Tag.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'itemId': itemId,
        'startMs': startMs,
        'endMs': endMs,
        'tags': tags.map((e) => e.toJson()).toList(),
      };
}

class KeyPeriodMutationResult {
  const KeyPeriodMutationResult({
    required this.keyPeriod,
    required this.correction,
  });

  final KeyPeriodKnowledge keyPeriod;
  final Correction correction;

  factory KeyPeriodMutationResult.fromJson(Map<String, dynamic> json) => KeyPeriodMutationResult(
        keyPeriod: KeyPeriodKnowledge.fromJson(json['keyPeriod'] as Map<String, dynamic>),
        correction: Correction.fromJson(json['correction'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'keyPeriod': keyPeriod.toJson(),
        'correction': correction.toJson(),
      };
}

class KillSwitchState {
  const KillSwitchState({
    required this.enabled,
    this.reason,
  });

  final bool enabled;
  final String? reason;

  factory KillSwitchState.fromJson(Map<String, dynamic> json) => KillSwitchState(
        enabled: json['enabled'] as bool,
        reason: json['reason'] == null ? null : json['reason'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'reason': reason,
      };
}

enum KnowledgeSource {
  metadata('metadata'),
  model('model'),
  human('human');

  const KnowledgeSource(this.wire);

  final String wire;

  static KnowledgeSource fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

class LibraryExport {
  const LibraryExport({
    required this.items,
    required this.tags,
    required this.persons,
    required this.comments,
    required this.corrections,
    required this.exportedAt,
  });

  final List<Item> items;
  final List<Tag> tags;
  final List<Person> persons;
  final List<Comment> comments;
  final List<Correction> corrections;
  final String exportedAt;

  factory LibraryExport.fromJson(Map<String, dynamic> json) => LibraryExport(
        items: (json['items'] as List<dynamic>).map((e) => Item.fromJson(e as Map<String, dynamic>)).toList(),
        tags: (json['tags'] as List<dynamic>).map((e) => Tag.fromJson(e as Map<String, dynamic>)).toList(),
        persons: (json['persons'] as List<dynamic>).map((e) => Person.fromJson(e as Map<String, dynamic>)).toList(),
        comments: (json['comments'] as List<dynamic>).map((e) => Comment.fromJson(e as Map<String, dynamic>)).toList(),
        corrections: (json['corrections'] as List<dynamic>).map((e) => Correction.fromJson(e as Map<String, dynamic>)).toList(),
        exportedAt: json['exportedAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'items': items.map((e) => e.toJson()).toList(),
        'tags': tags.map((e) => e.toJson()).toList(),
        'persons': persons.map((e) => e.toJson()).toList(),
        'comments': comments.map((e) => e.toJson()).toList(),
        'corrections': corrections.map((e) => e.toJson()).toList(),
        'exportedAt': exportedAt,
      };
}

class LinkPeopleResponse {
  const LinkPeopleResponse({
    required this.appearances,
  });

  final List<PersonAppearance> appearances;

  factory LinkPeopleResponse.fromJson(Map<String, dynamic> json) => LinkPeopleResponse(
        appearances: (json['appearances'] as List<dynamic>).map((e) => PersonAppearance.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'appearances': appearances.map((e) => e.toJson()).toList(),
      };
}

enum LinkState {
  suggested('suggested'),
  confirmed('confirmed');

  const LinkState(this.wire);

  final String wire;

  static LinkState fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

class Person {
  const Person({
    required this.id,
    this.name,
    required this.linkState,
    required this.createdAt,
  });

  final String id;
  final String? name;
  final LinkState linkState;
  final String createdAt;

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String,
        name: json['name'] == null ? null : json['name'] as String,
        linkState: LinkState.fromWire(json['linkState'] as String),
        createdAt: json['createdAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'linkState': linkState.wire,
        'createdAt': createdAt,
      };
}

class PersonAppearance {
  const PersonAppearance({
    required this.id,
    this.personId,
    this.itemId,
    this.keyPeriodId,
    required this.linkState,
    required this.createdAt,
  });

  final String id;
  final String? personId;
  final String? itemId;
  final String? keyPeriodId;
  final LinkState linkState;
  final String createdAt;

  factory PersonAppearance.fromJson(Map<String, dynamic> json) => PersonAppearance(
        id: json['id'] as String,
        personId: json['personId'] == null ? null : json['personId'] as String,
        itemId: json['itemId'] == null ? null : json['itemId'] as String,
        keyPeriodId: json['keyPeriodId'] == null ? null : json['keyPeriodId'] as String,
        linkState: LinkState.fromWire(json['linkState'] as String),
        createdAt: json['createdAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'personId': personId,
        'itemId': itemId,
        'keyPeriodId': keyPeriodId,
        'linkState': linkState.wire,
        'createdAt': createdAt,
      };
}

class PersonDetail {
  const PersonDetail({
    required this.id,
    this.name,
    required this.linkState,
    required this.createdAt,
    required this.appearances,
  });

  final String id;
  final String? name;
  final LinkState linkState;
  final String createdAt;
  final List<PersonAppearance> appearances;

  factory PersonDetail.fromJson(Map<String, dynamic> json) => PersonDetail(
        id: json['id'] as String,
        name: json['name'] == null ? null : json['name'] as String,
        linkState: LinkState.fromWire(json['linkState'] as String),
        createdAt: json['createdAt'] as String,
        appearances: (json['appearances'] as List<dynamic>).map((e) => PersonAppearance.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'linkState': linkState.wire,
        'createdAt': createdAt,
        'appearances': appearances.map((e) => e.toJson()).toList(),
      };
}

class PrePassAppearanceInput {
  const PrePassAppearanceInput({
    this.keyPeriodIndex,
    required this.embedding,
    required this.embeddingModelId,
  });

  final int? keyPeriodIndex;
  final List<double> embedding;
  final String embeddingModelId;

  factory PrePassAppearanceInput.fromJson(Map<String, dynamic> json) => PrePassAppearanceInput(
        keyPeriodIndex: json['keyPeriodIndex'] == null ? null : (json['keyPeriodIndex'] as num).toInt(),
        embedding: (json['embedding'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        embeddingModelId: json['embeddingModelId'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'keyPeriodIndex': keyPeriodIndex,
        'embedding': embedding.map((e) => e).toList(),
        'embeddingModelId': embeddingModelId,
      };
}

class PrePassKeyPeriodInput {
  const PrePassKeyPeriodInput({
    required this.startMs,
    required this.endMs,
  });

  final int startMs;
  final int endMs;

  factory PrePassKeyPeriodInput.fromJson(Map<String, dynamic> json) => PrePassKeyPeriodInput(
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'startMs': startMs,
        'endMs': endMs,
      };
}

class PrePassResult {
  const PrePassResult({
    this.contentHash,
    this.perceptualHash,
    this.capturedAt,
    this.where,
    this.durationMs,
    this.keyPeriods,
    this.appearances,
  });

  final String? contentHash;
  final String? perceptualHash;
  final String? capturedAt;
  final PrePassWhere? where;
  final int? durationMs;
  final List<PrePassKeyPeriodInput>? keyPeriods;
  final List<PrePassAppearanceInput>? appearances;

  factory PrePassResult.fromJson(Map<String, dynamic> json) => PrePassResult(
        contentHash: json['contentHash'] == null ? null : json['contentHash'] as String,
        perceptualHash: json['perceptualHash'] == null ? null : json['perceptualHash'] as String,
        capturedAt: json['capturedAt'] == null ? null : json['capturedAt'] as String,
        where: json['where'] == null ? null : PrePassWhere.fromJson(json['where'] as Map<String, dynamic>),
        durationMs: json['durationMs'] == null ? null : (json['durationMs'] as num).toInt(),
        keyPeriods: json['keyPeriods'] == null ? null : (json['keyPeriods'] as List<dynamic>).map((e) => PrePassKeyPeriodInput.fromJson(e as Map<String, dynamic>)).toList(),
        appearances: json['appearances'] == null ? null : (json['appearances'] as List<dynamic>).map((e) => PrePassAppearanceInput.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contentHash': contentHash,
        'perceptualHash': perceptualHash,
        'capturedAt': capturedAt,
        'where': where?.toJson(),
        'durationMs': durationMs,
        'keyPeriods': keyPeriods?.map((e) => e.toJson()).toList(),
        'appearances': appearances?.map((e) => e.toJson()).toList(),
      };
}

class PrePassResultResponse {
  const PrePassResultResponse({
    required this.item,
    required this.keyPeriodIds,
    required this.appearanceIds,
    required this.tagIds,
  });

  final Item item;
  final List<String> keyPeriodIds;
  final List<String> appearanceIds;
  final List<String> tagIds;

  factory PrePassResultResponse.fromJson(Map<String, dynamic> json) => PrePassResultResponse(
        item: Item.fromJson(json['item'] as Map<String, dynamic>),
        keyPeriodIds: (json['keyPeriodIds'] as List<dynamic>).map((e) => e as String).toList(),
        appearanceIds: (json['appearanceIds'] as List<dynamic>).map((e) => e as String).toList(),
        tagIds: (json['tagIds'] as List<dynamic>).map((e) => e as String).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item': item.toJson(),
        'keyPeriodIds': keyPeriodIds.map((e) => e).toList(),
        'appearanceIds': appearanceIds.map((e) => e).toList(),
        'tagIds': tagIds.map((e) => e).toList(),
      };
}

class PrePassWhere {
  const PrePassWhere({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;

  factory PrePassWhere.fromJson(Map<String, dynamic> json) => PrePassWhere(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lat': lat,
        'lng': lng,
      };
}

enum ProcessingStatus {
  pending('pending'),
  awaitingModelAccess('awaiting_model_access'),
  processing('processing'),
  tagged('tagged'),
  failed('failed'),
  cancelled('cancelled');

  const ProcessingStatus(this.wire);

  final String wire;

  static ProcessingStatus fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

class ReassignAppearance {
  const ReassignAppearance({
    required this.personId,
  });

  final String personId;

  factory ReassignAppearance.fromJson(Map<String, dynamic> json) => ReassignAppearance(
        personId: json['personId'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'personId': personId,
      };
}

class RecordAnalysisRef {
  const RecordAnalysisRef({
    required this.analysisRef,
  });

  final String analysisRef;

  factory RecordAnalysisRef.fromJson(Map<String, dynamic> json) => RecordAnalysisRef(
        analysisRef: json['analysisRef'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'analysisRef': analysisRef,
      };
}

class RenamePerson {
  const RenamePerson({
    this.name,
  });

  final String? name;

  factory RenamePerson.fromJson(Map<String, dynamic> json) => RenamePerson(
        name: json['name'] == null ? null : json['name'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
      };
}

enum SourceType {
  local('local');

  const SourceType(this.wire);

  final String wire;

  static SourceType fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

class SplitPerson {
  const SplitPerson({
    required this.appearanceIds,
  });

  final List<String> appearanceIds;

  factory SplitPerson.fromJson(Map<String, dynamic> json) => SplitPerson(
        appearanceIds: (json['appearanceIds'] as List<dynamic>).map((e) => e as String).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'appearanceIds': appearanceIds.map((e) => e).toList(),
      };
}

class Tag {
  const Tag({
    required this.id,
    this.itemId,
    this.keyPeriodId,
    required this.dimension,
    required this.value,
    required this.source,
    required this.status,
    this.correctedFromTagId,
    this.confidence,
    this.provider,
    this.modelId,
    required this.schemaVersion,
    required this.createdAt,
  });

  final String id;
  final String? itemId;
  final String? keyPeriodId;
  final String dimension;
  final String value;
  final KnowledgeSource source;
  final TagStatus status;
  final String? correctedFromTagId;
  final double? confidence;
  final String? provider;
  final String? modelId;
  final int schemaVersion;
  final String createdAt;

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id'] as String,
        itemId: json['itemId'] == null ? null : json['itemId'] as String,
        keyPeriodId: json['keyPeriodId'] == null ? null : json['keyPeriodId'] as String,
        dimension: json['dimension'] as String,
        value: json['value'] as String,
        source: KnowledgeSource.fromWire(json['source'] as String),
        status: TagStatus.fromWire(json['status'] as String),
        correctedFromTagId: json['correctedFromTagId'] == null ? null : json['correctedFromTagId'] as String,
        confidence: json['confidence'] == null ? null : (json['confidence'] as num).toDouble(),
        provider: json['provider'] == null ? null : json['provider'] as String,
        modelId: json['modelId'] == null ? null : json['modelId'] as String,
        schemaVersion: (json['schemaVersion'] as num).toInt(),
        createdAt: json['createdAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'itemId': itemId,
        'keyPeriodId': keyPeriodId,
        'dimension': dimension,
        'value': value,
        'source': source.wire,
        'status': status.wire,
        'correctedFromTagId': correctedFromTagId,
        'confidence': confidence,
        'provider': provider,
        'modelId': modelId,
        'schemaVersion': schemaVersion,
        'createdAt': createdAt,
      };
}

class TagMutationResult {
  const TagMutationResult({
    required this.tag,
    required this.correction,
  });

  final Tag tag;
  final Correction correction;

  factory TagMutationResult.fromJson(Map<String, dynamic> json) => TagMutationResult(
        tag: Tag.fromJson(json['tag'] as Map<String, dynamic>),
        correction: Correction.fromJson(json['correction'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tag': tag.toJson(),
        'correction': correction.toJson(),
      };
}

enum TagStatus {
  active('active'),
  superseded('superseded'),
  removed('removed');

  const TagStatus(this.wire);

  final String wire;

  static TagStatus fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  @override
  String toString() => wire;
}

class UndoCorrectionResult {
  const UndoCorrectionResult({
    required this.correction,
    required this.restored,
  });

  final Correction correction;
  final UndoCorrectionResultRestored restored;

  factory UndoCorrectionResult.fromJson(Map<String, dynamic> json) => UndoCorrectionResult(
        correction: Correction.fromJson(json['correction'] as Map<String, dynamic>),
        restored: UndoCorrectionResultRestored.fromJson(json['restored'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'correction': correction.toJson(),
        'restored': restored.toJson(),
      };
}

class UndoCorrectionResultRestored {
  const UndoCorrectionResultRestored({
    required this.kind,
    this.tag,
    this.item,
    this.keyPeriod,
  });

  final String kind;
  final Tag? tag;
  final Item? item;
  final KeyPeriodKnowledge? keyPeriod;

  factory UndoCorrectionResultRestored.fromJson(Map<String, dynamic> json) => UndoCorrectionResultRestored(
        kind: json['kind'] as String,
        tag: json['tag'] == null ? null : Tag.fromJson(json['tag'] as Map<String, dynamic>),
        item: json['item'] == null ? null : Item.fromJson(json['item'] as Map<String, dynamic>),
        keyPeriod: json['keyPeriod'] == null ? null : KeyPeriodKnowledge.fromJson(json['keyPeriod'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'tag': tag?.toJson(),
        'item': item?.toJson(),
        'keyPeriod': keyPeriod?.toJson(),
      };
}

class UploadGrant {
  const UploadGrant({
    required this.uploadUrl,
    required this.expiresAt,
  });

  final String uploadUrl;
  final String expiresAt;

  factory UploadGrant.fromJson(Map<String, dynamic> json) => UploadGrant(
        uploadUrl: json['uploadUrl'] as String,
        expiresAt: json['expiresAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uploadUrl': uploadUrl,
        'expiresAt': expiresAt,
      };
}

class UsageSummary {
  const UsageSummary({
    required this.softLimitCents,
    required this.hardLimitCents,
    required this.reservedCents,
    required this.spentCents,
    required this.killSwitch,
    this.softLimitExceeded,
    this.pauseReason,
  });

  final int softLimitCents;
  final int hardLimitCents;
  final int reservedCents;
  final int spentCents;
  final KillSwitchState killSwitch;
  final bool? softLimitExceeded;
  final String? pauseReason;

  factory UsageSummary.fromJson(Map<String, dynamic> json) => UsageSummary(
        softLimitCents: (json['softLimitCents'] as num).toInt(),
        hardLimitCents: (json['hardLimitCents'] as num).toInt(),
        reservedCents: (json['reservedCents'] as num).toInt(),
        spentCents: (json['spentCents'] as num).toInt(),
        killSwitch: KillSwitchState.fromJson(json['killSwitch'] as Map<String, dynamic>),
        softLimitExceeded: json['softLimitExceeded'] == null ? null : json['softLimitExceeded'] as bool,
        pauseReason: json['pauseReason'] == null ? null : json['pauseReason'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'softLimitCents': softLimitCents,
        'hardLimitCents': hardLimitCents,
        'reservedCents': reservedCents,
        'spentCents': spentCents,
        'killSwitch': killSwitch.toJson(),
        'softLimitExceeded': softLimitExceeded,
        'pauseReason': pauseReason,
      };
}

