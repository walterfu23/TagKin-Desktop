import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show itemsRepositoryProvider, personsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/knowledge/tag_edit_dialog.dart';
import 'package:tagkin_desktop/library/item_detail_edits.dart';
import 'package:tagkin_desktop/library/item_fields_group.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/review/key_period_scrubber.dart';
import 'package:tagkin_desktop/review/knowledge_view.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/review/media_viewer.dart';
import 'package:tagkin_desktop/review/review_controller.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';

/// Review screen: local media + approved knowledge + corrections/comments.
///
/// Embedded below D2/D7 metadata on the item detail screen. D9 adds
/// per-crop / whole-item person assign. D10 owns tag /
/// key-period corrections and comments. D12 owns per-screen
/// LIFO undo/redo (Cmd/Ctrl+Z) for this Review page.
class ItemReviewSection extends ConsumerStatefulWidget {
  const ItemReviewSection({
    super.key,
    required this.itemId,
    this.item,
    this.openVideo = true,
    this.edits,
    this.embedSaveButton = true,
  });

  final String itemId;

  /// When set, the Status / Type / Captured / Added / File group can render
  /// before knowledge loads (Who–Where show — until then).
  final Item? item;

  /// When false, skips native media_kit open (widget tests).
  final bool openVideo;

  /// Shared dirty/Save hooks for the item AppBar. When null, this section
  /// owns a local [ItemDetailEdits] and [embedSaveButton] shows Save here.
  final ItemDetailEdits? edits;

  /// Show an in-body Save when the AppBar is not hosting one.
  final bool embedSaveButton;

  @override
  ConsumerState<ItemReviewSection> createState() => _ItemReviewSectionState();
}

class _ItemReviewSectionState extends ConsumerState<ItemReviewSection> {
  Player? _player;
  VideoController? _videoController;
  String? _openedPath;
  bool _saving = false;
  String? _assignError;
  late final UndoController _undoStack = UndoController();
  late final ItemDetailEdits _edits = widget.edits ?? ItemDetailEdits();
  bool _ownsEdits = false;
  List<Person> _persons = const [];
  Map<String, String> _personNamesById = {};
  String _comment = '';
  String _commentBaseline = '';
  final Map<String, PersonAssignIntent> _cropIntents = {};
  final Map<String, PersonAssignIntent> _appearanceIntents = {};
  final Map<String, PersonAssignIntent> _exclusionIntents = {};
  final List<PersonAssignIntent> _pendingItemAssigns = [];
  bool _baselineReady = false;

  @override
  void initState() {
    super.initState();
    _ownsEdits = widget.edits == null;
    _edits.save = _save;
    _edits.discard = _discard;
    _edits.confirmLeave = _confirmLeave;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final review = ref.read(reviewControllerProvider(widget.itemId));
      review.undoStack = _undoStack;
      review.load();
      unawaited(_loadPersonNames());
    });
  }

  @override
  void didUpdateWidget(covariant ItemReviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _edits.save = _save;
    _edits.discard = _discard;
    _edits.confirmLeave = _confirmLeave;
  }

  Future<void> _loadPersonNames() async {
    try {
      final people = await ref.read(personsRepositoryProvider).listPersons();
      if (!mounted) return;
      setState(() {
        _persons = people;
        _personNamesById = {for (final p in people) p.id: p.name};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _persons = const [];
        _personNamesById = {};
      });
    }
  }

  @override
  void dispose() {
    _edits.save = null;
    _edits.discard = null;
    _edits.confirmLeave = null;
    if (_ownsEdits) _edits.dispose();
    _undoStack.dispose();
    _disposePlayer();
    super.dispose();
  }

  void _disposePlayer() {
    _player?.dispose();
    _player = null;
    _videoController = null;
    _openedPath = null;
  }

  Future<void> _ensureVideoOpen(LocalMediaResolution media) async {
    if (!widget.openVideo) return;
    if (!media.isAvailable) return;
    final path = media.path;
    if (path == null || path == _openedPath) return;

    _disposePlayer();
    try {
      final opened = await openLocalVideo(media.file!);
      if (!mounted) {
        await opened.player.dispose();
        return;
      }
      setState(() {
        _player = opened.player;
        _videoController = opened.controller;
        _openedPath = path;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _player = null;
        _videoController = null;
        _openedPath = null;
      });
    }
  }

  PersonAssignIntent _baselineCrop(ItemKnowledge knowledge, String tagId) {
    final appearance = appearanceForWhoTag(knowledge, tagId);
    return PersonAssignIntent(personId: appearance?.personId);
  }

  PersonAssignIntent _baselineAppearance(PersonAppearance appearance) {
    return PersonAssignIntent(personId: appearance.personId);
  }

  bool get _isDirty {
    final review = ref.read(reviewControllerProvider(widget.itemId));
    final knowledge = review.knowledge;
    if (_comment.trim() != _commentBaseline.trim()) return true;
    if (_pendingItemAssigns.isNotEmpty) return true;
    if (_exclusionIntents.isNotEmpty) return true;
    if (knowledge == null) return _cropIntents.isNotEmpty || _appearanceIntents.isNotEmpty;
    for (final e in _cropIntents.entries) {
      if (!e.value.sameAs(_baselineCrop(knowledge, e.key))) return true;
    }
    for (final e in _appearanceIntents.entries) {
      PersonAppearance? appearance;
      for (final a in knowledge.appearances) {
        if (a.id == e.key) {
          appearance = a;
          break;
        }
      }
      if (appearance == null) return true;
      if (!e.value.sameAs(_baselineAppearance(appearance))) return true;
    }
    return false;
  }

  void _publishDirty() {
    _edits.update(dirty: _isDirty, saving: _saving);
  }

  void _adoptBaseline(ReviewController review) {
    if (_baselineReady) return;
    if (_isDirty) {
      _baselineReady = true;
      return;
    }
    setState(() {
      _comment = review.itemComments.firstOrNull?.body ?? '';
      _commentBaseline = _comment;
      _cropIntents.clear();
      _appearanceIntents.clear();
      _exclusionIntents.clear();
      _pendingItemAssigns.clear();
      _baselineReady = true;
    });
    _publishDirty();
  }

  void _mutateDraft(VoidCallback change, {required String label}) {
    final beforeComment = _comment;
    final beforeCrops = Map<String, PersonAssignIntent>.from(_cropIntents);
    final beforeAppearances =
        Map<String, PersonAssignIntent>.from(_appearanceIntents);
    final beforeExclusions =
        Map<String, PersonAssignIntent>.from(_exclusionIntents);
    final beforePending = List<PersonAssignIntent>.from(_pendingItemAssigns);
    setState(change);
    final afterComment = _comment;
    final afterCrops = Map<String, PersonAssignIntent>.from(_cropIntents);
    final afterAppearances =
        Map<String, PersonAssignIntent>.from(_appearanceIntents);
    final afterExclusions =
        Map<String, PersonAssignIntent>.from(_exclusionIntents);
    final afterPending = List<PersonAssignIntent>.from(_pendingItemAssigns);
    if (beforeComment == afterComment &&
        _mapEquals(beforeCrops, afterCrops) &&
        _mapEquals(beforeAppearances, afterAppearances) &&
        _mapEquals(beforeExclusions, afterExclusions) &&
        _listEquals(beforePending, afterPending)) {
      _publishDirty();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _undoStack.push(
      CallbackUndoableAction(
        label: label,
        onUndo: () async {
          setState(() {
            _comment = beforeComment;
            _cropIntents
              ..clear()
              ..addAll(beforeCrops);
            _appearanceIntents
              ..clear()
              ..addAll(beforeAppearances);
            _exclusionIntents
              ..clear()
              ..addAll(beforeExclusions);
            _pendingItemAssigns
              ..clear()
              ..addAll(beforePending);
          });
          _publishDirty();
        },
        onRedo: () async {
          setState(() {
            _comment = afterComment;
            _cropIntents
              ..clear()
              ..addAll(afterCrops);
            _appearanceIntents
              ..clear()
              ..addAll(afterAppearances);
            _exclusionIntents
              ..clear()
              ..addAll(afterExclusions);
            _pendingItemAssigns
              ..clear()
              ..addAll(afterPending);
          });
          _publishDirty();
        },
      ),
    );
    _publishDirty();
  }

  bool _mapEquals(
    Map<String, PersonAssignIntent> a,
    Map<String, PersonAssignIntent> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null || !e.value.sameAs(other)) return false;
    }
    return true;
  }

  bool _listEquals(List<PersonAssignIntent> a, List<PersonAssignIntent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].sameAs(b[i])) return false;
    }
    return true;
  }

  Future<void> _assignCrop(
    String tagId, {
    String? personId,
    String? name,
  }) async {
    _mutateDraft(
      () {
        _cropIntents[tagId] = PersonAssignIntent(
          personId: personId,
          name: name,
        );
      },
      label: 'Assign face',
    );
  }

  Future<void> _assignItem({String? personId, String? name}) async {
    _mutateDraft(
      () {
        _pendingItemAssigns.add(
          PersonAssignIntent(personId: personId, name: name),
        );
      },
      label: 'Assign item',
    );
  }

  Future<void> _reassignAppearance(
    String appearanceId, {
    String? personId,
    String? name,
  }) async {
    _mutateDraft(
      () {
        _appearanceIntents[appearanceId] = PersonAssignIntent(
          personId: personId,
          name: name,
        );
      },
      label: 'Reassign',
    );
  }

  Future<void> _unassignAppearance(String appearanceId) async {
    _mutateDraft(
      () {
        final knowledge =
            ref.read(reviewControllerProvider(widget.itemId)).knowledge;
        var fromCrop = false;
        if (knowledge != null) {
          for (final tag in whoFaceCropTags(knowledge)) {
            final ap = appearanceForWhoTag(knowledge, tag.id);
            if (ap?.id == appearanceId) {
              _cropIntents[tag.id] = const PersonAssignIntent(unassign: true);
              fromCrop = true;
            }
          }
        }
        if (!fromCrop) {
          _appearanceIntents[appearanceId] =
              const PersonAssignIntent(unassign: true);
        }
      },
      label: 'Unassign',
    );
  }

  Future<void> _excludeCrop(String tagId) async {
    _mutateDraft(
      () {
        _cropIntents[tagId] = const PersonAssignIntent(exclude: true);
      },
      label: 'Exclude face',
    );
  }

  Future<void> _includeDraftCrop(String tagId) async {
    _mutateDraft(
      () {
        _cropIntents.remove(tagId);
      },
      label: 'Include face',
    );
  }

  Future<void> _includeExclusion(String exclusionId) async {
    _mutateDraft(
      () {
        _exclusionIntents[exclusionId] =
            const PersonAssignIntent(include: true);
      },
      label: 'Include face',
    );
  }

  Future<void> _assignIncludedExclusion(
    String exclusionId, {
    String? personId,
    String? name,
  }) async {
    _mutateDraft(
      () {
        _exclusionIntents[exclusionId] = PersonAssignIntent(
          include: true,
          personId: personId,
          name: name,
        );
      },
      label: 'Assign face',
    );
  }

  Future<void> _excludeIncludedExclusion(String exclusionId) async {
    _mutateDraft(
      () {
        _exclusionIntents.remove(exclusionId);
      },
      label: 'Exclude face',
    );
  }

  Future<void> _save() async {
    if (_saving || !_isDirty) return;
    final review = ref.read(reviewControllerProvider(widget.itemId));
    final knowledge = review.knowledge;
    final previousComment = _commentBaseline;
    final previousCrop = knowledge == null
        ? const <String, PersonAssignIntent>{}
        : {
            for (final tag in whoFaceCropTags(knowledge))
              tag.id: _baselineCrop(knowledge, tag.id),
          };
    final previousAppearances = knowledge == null
        ? const <String, PersonAssignIntent>{}
        : {
            for (final a in itemLevelPersonAssignments(knowledge))
              a.id: _baselineAppearance(a),
          };
    final forwardComment = _comment;
    final forwardCrops = Map<String, PersonAssignIntent>.from(_cropIntents);
    final forwardAppearances =
        Map<String, PersonAssignIntent>.from(_appearanceIntents);
    final forwardExclusions =
        Map<String, PersonAssignIntent>.from(_exclusionIntents);
    final forwardPending = List<PersonAssignIntent>.from(_pendingItemAssigns);
    final createdExclusionIds = <String>[];
    final includedExclusionTagIds = <({String exclusionId, String? tagId})>[];

    setState(() {
      _saving = true;
      _assignError = null;
    });
    _publishDirty();
    try {
      if (review.knowledge == null) {
        await review.load();
      }
      final liveKnowledge = review.knowledge ?? knowledge;
      if (forwardExclusions.isNotEmpty) {
        final items = ref.read(itemsRepositoryProvider);
        for (final e in forwardExclusions.entries) {
          if (!e.value.include) continue;
          WhoExclusion? exclusion;
          if (liveKnowledge != null) {
            for (final x in liveKnowledge.whoExclusions) {
              if (x.id == e.key) {
                exclusion = x;
                break;
              }
            }
          }
          includedExclusionTagIds.add(
            (exclusionId: e.key, tagId: exclusion?.createdFromTagId),
          );
          await items.undoWhoExclusion(widget.itemId, e.key);
          if (e.value.hasTarget && exclusion?.createdFromTagId != null) {
            await items.assignPersonToItem(
              widget.itemId,
              personId: e.value.personId,
              name: e.value.name,
              tagId: exclusion!.createdFromTagId,
            );
          }
        }
      }
      if (forwardCrops.isNotEmpty ||
          forwardAppearances.isNotEmpty ||
          forwardPending.isNotEmpty) {
        createdExclusionIds.addAll(
          await _applyPersonIntents(
            knowledge: review.knowledge ?? knowledge,
            cropIntents: forwardCrops,
            appearanceIntents: forwardAppearances,
            pendingItemAssigns: forwardPending,
          ),
        );
      }
      await review.saveItemComment(forwardComment);
      if (!mounted) return;
      await _loadPersonNames();
      await review.load();
      if (!mounted) return;
      _comment = review.itemComments.firstOrNull?.body ?? '';
      _commentBaseline = _comment;
      _cropIntents.clear();
      _appearanceIntents.clear();
      _exclusionIntents.clear();
      _pendingItemAssigns.clear();
      _baselineReady = true;
      _undoStack.clear();
      _undoStack.push(
        CallbackUndoableAction(
          label: 'Save item',
          onUndo: () async {
            final items = ref.read(itemsRepositoryProvider);
            for (final id in createdExclusionIds) {
              await items.undoWhoExclusion(widget.itemId, id);
            }
            for (final included in includedExclusionTagIds) {
              final tagId = included.tagId;
              if (tagId != null) {
                await items.createWhoExclusion(widget.itemId, tagId);
              }
            }
            if (previousCrop.isNotEmpty || previousAppearances.isNotEmpty) {
              await _applyPersonIntents(
                knowledge: ref.read(reviewControllerProvider(widget.itemId)).knowledge,
                cropIntents: previousCrop,
                appearanceIntents: previousAppearances,
                pendingItemAssigns: const [],
              );
            }
            await review.saveItemComment(previousComment);
            if (!mounted) return;
            await _loadPersonNames();
            await review.load();
            if (!mounted) return;
            setState(() {
              _comment = previousComment;
              _commentBaseline = previousComment;
              _cropIntents.clear();
              _appearanceIntents.clear();
              _exclusionIntents.clear();
              _pendingItemAssigns.clear();
            });
            _publishDirty();
          },
          onRedo: () async {
            if (forwardExclusions.isNotEmpty) {
              final items = ref.read(itemsRepositoryProvider);
              final live =
                  ref.read(reviewControllerProvider(widget.itemId)).knowledge;
              for (final e in forwardExclusions.entries) {
                if (!e.value.include) continue;
                String? tagId;
                for (final included in includedExclusionTagIds) {
                  if (included.exclusionId == e.key) {
                    tagId = included.tagId;
                    break;
                  }
                }
                WhoExclusion? exclusion;
                if (live != null) {
                  for (final x in live.whoExclusions) {
                    if (x.id == e.key ||
                        (tagId != null && x.createdFromTagId == tagId)) {
                      exclusion = x;
                      break;
                    }
                  }
                }
                if (exclusion == null) continue;
                await items.undoWhoExclusion(widget.itemId, exclusion.id);
                if (e.value.hasTarget &&
                    exclusion.createdFromTagId != null) {
                  await items.assignPersonToItem(
                    widget.itemId,
                    personId: e.value.personId,
                    name: e.value.name,
                    tagId: exclusion.createdFromTagId,
                  );
                }
              }
            }
            if (forwardCrops.isNotEmpty ||
                forwardAppearances.isNotEmpty ||
                forwardPending.isNotEmpty) {
              await _applyPersonIntents(
                knowledge: ref.read(reviewControllerProvider(widget.itemId)).knowledge,
                cropIntents: forwardCrops,
                appearanceIntents: forwardAppearances,
                pendingItemAssigns: forwardPending,
              );
            }
            await review.saveItemComment(forwardComment);
            if (!mounted) return;
            await _loadPersonNames();
            await review.load();
            if (!mounted) return;
            setState(() {
              _comment = forwardComment;
              _commentBaseline = forwardComment;
              _cropIntents.clear();
              _appearanceIntents.clear();
              _exclusionIntents.clear();
              _pendingItemAssigns.clear();
            });
            _publishDirty();
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _assignError = '$e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _publishDirty();
      }
    }
  }

  Future<List<String>> _applyPersonIntents({
    required ItemKnowledge? knowledge,
    required Map<String, PersonAssignIntent> cropIntents,
    required Map<String, PersonAssignIntent> appearanceIntents,
    required List<PersonAssignIntent> pendingItemAssigns,
  }) async {
    final items = ref.read(itemsRepositoryProvider);
    final persons = ref.read(personsRepositoryProvider);
    final unlinked = <String>{};
    final createdExclusionIds = <String>[];
    for (final e in cropIntents.entries) {
      final intent = e.value;
      final appearance =
          knowledge == null ? null : appearanceForWhoTag(knowledge, e.key);
      if (intent.exclude) {
        final created = await items.createWhoExclusion(widget.itemId, e.key);
        createdExclusionIds.add(created.exclusion.id);
        continue;
      }
      if (intent.unassign) {
        if (appearance?.id != null) {
          await persons.unlinkAppearance(appearance!.id);
          unlinked.add(appearance.id);
        }
        continue;
      }
      if (!intent.hasTarget) continue;
      if (appearance?.id != null &&
          intent.personId != null &&
          intent.name == null) {
        await persons.reassignAppearance(
          appearance!.id,
          personId: intent.personId,
        );
      } else {
        await items.assignPersonToItem(
          widget.itemId,
          personId: intent.personId,
          name: intent.name,
          tagId: e.key,
        );
      }
    }
    for (final e in appearanceIntents.entries) {
      final intent = e.value;
      if (intent.unassign) {
        if (!unlinked.contains(e.key)) {
          await persons.unlinkAppearance(e.key);
        }
        continue;
      }
      if (!intent.hasTarget) continue;
      await persons.reassignAppearance(
        e.key,
        personId: intent.personId,
        name: intent.name,
      );
    }
    for (final intent in pendingItemAssigns) {
      if (!intent.hasTarget) continue;
      await items.assignPersonToItem(
        widget.itemId,
        personId: intent.personId,
        name: intent.name,
      );
    }
    return createdExclusionIds;
  }

  void _discard() {
    setState(() {
      _comment = _commentBaseline;
      _cropIntents.clear();
      _appearanceIntents.clear();
      _exclusionIntents.clear();
      _pendingItemAssigns.clear();
    });
    _undoStack.clear();
    _publishDirty();
  }

  Future<bool> _confirmLeave() async {
    if (!_isDirty) return true;
    if (!mounted) return false;
    final choice = await showDialog<_ItemDetailLeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('item-detail-dirty-dialog'),
        title: const Text('Save item?'),
        content: const Text(
          'You have unsaved changes. Save before leaving?',
        ),
        actions: [
          TextButton(
            key: const Key('item-detail-dirty-discard'),
            onPressed: () =>
                Navigator.pop(ctx, _ItemDetailLeaveChoice.discard),
            child: const Text('Discard'),
          ),
          TextButton(
            key: const Key('item-detail-dirty-cancel'),
            onPressed: () =>
                Navigator.pop(ctx, _ItemDetailLeaveChoice.cancel),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('item-detail-dirty-save'),
            onPressed: () => Navigator.pop(ctx, _ItemDetailLeaveChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    switch (choice) {
      case _ItemDetailLeaveChoice.discard:
        _discard();
        return true;
      case _ItemDetailLeaveChoice.save:
        await _save();
        return !_isDirty;
      case _ItemDetailLeaveChoice.cancel:
      case null:
        return false;
    }
  }

  Future<void> _openPerson(String personId) async {
    final ok = await _confirmLeave();
    if (!ok || !mounted) return;
    final container = ProviderScope.containerOf(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UndoSelectableRoute(
          child: UncontrolledProviderScope(
            container: container,
            child: PersonDetailPage(personId: personId),
          ),
        ),
      ),
    );
    if (mounted) {
      await ref.read(reviewControllerProvider(widget.itemId)).load();
    }
  }

  Future<void> _editBounds(
    ReviewController review,
    KeyPeriodKnowledge period,
  ) async {
    final result = await showKeyPeriodBoundsDialog(
      context,
      startMs: period.startMs,
      endMs: period.endMs,
    );
    if (result == null) return;
    await review.correctKeyPeriodBounds(
      keyPeriodId: period.id,
      startMs: result.startMs,
      endMs: result.endMs,
    );
  }

  List<String> _whoCsvNames(ItemKnowledge knowledge) {
    final names = <String>[];
    final seen = <String>{};
    void add(String? raw) {
      final n = raw?.trim();
      if (n == null || n.isEmpty || !seen.add(n)) return;
      names.add(n);
    }

    final crops = whoFaceCropTags(knowledge);
    if (crops.isNotEmpty) {
      for (final tag in crops) {
        final appearance = appearanceForWhoTag(knowledge, tag.id);
        final intent = _cropIntents[tag.id];
        if (intent?.unassign == true || intent?.exclude == true) continue;
        if (intent?.name != null) {
          add(intent!.name);
        } else if (intent?.personId != null) {
          add(_personNamesById[intent!.personId]);
        } else {
          add(_personNamesById[appearance?.personId]);
        }
      }
    } else {
      for (final appearance in itemLevelPersonAssignments(knowledge)) {
        final intent = _appearanceIntents[appearance.id];
        if (intent?.unassign == true) continue;
        if (intent?.name != null) {
          add(intent!.name);
        } else if (intent?.personId != null) {
          add(_personNamesById[intent!.personId]);
        } else {
          add(_personNamesById[appearance.personId]);
        }
      }
      for (final pending in _pendingItemAssigns) {
        if (pending.name != null) {
          add(pending.name);
        } else {
          add(_personNamesById[pending.personId]);
        }
      }
    }
    for (final intent in _exclusionIntents.values) {
      if (!intent.include) continue;
      if (intent.name != null) {
        add(intent.name);
      } else {
        add(_personNamesById[intent.personId]);
      }
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    _edits.save = _save;
    _edits.discard = _discard;
    _edits.confirmLeave = _confirmLeave;
    final review = ref.watch(reviewControllerProvider(widget.itemId));
    final showFaceOverlays =
        ref.watch(desktopPrefsProvider).showFaceOverlays;

    return ListenableBuilder(
      listenable: review,
      builder: (context, _) {
        final knowledge = review.knowledge;
        final media = review.media;
        if (knowledge != null &&
            media != null &&
            knowledge.item.type == ItemType.video &&
            media.isAvailable) {
          // Schedule open after this frame (avoid setState during build).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureVideoOpen(media);
          });
        }

        final fieldsItem = knowledge?.item ?? widget.item;
        if (review.phase == ReviewPhase.ready ||
            review.phase == ReviewPhase.busy) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _adoptBaseline(review);
          });
        }

        return ActiveUndoHost(
          controller: _undoStack,
          child: UndoShortcuts(
          controller: _undoStack,
          onError: (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$e')),
            );
          },
          child: Column(
          key: const Key('item-review'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.embedSaveButton) ...[
              Align(
                alignment: Alignment.centerRight,
                child: ListenableBuilder(
                  listenable: _edits,
                  builder: (context, _) {
                    return FilledButton(
                      key: const Key('item-detail-save'),
                      onPressed: _edits.isDirty && !_edits.saving ? _save : null,
                      child: const Text('Save'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (fieldsItem != null) ...[
              ItemFieldsGroup(
                item: fieldsItem,
                knowledge: knowledge,
                personNamesById: _personNamesById,
                whoPersonNames:
                    knowledge == null ? null : _whoCsvNames(knowledge),
                omittedWhoTagIds: {
                  for (final e in _cropIntents.entries)
                    if (e.value.exclude) e.key,
                },
                commentText: _comment,
                commentEnabled: !review.isBusy && !_saving,
                onCommentChanged: (value) {
                  setState(() => _comment = value);
                  _publishDirty();
                },
              ),
              const SizedBox(height: 12),
            ],
            if (knowledge != null) ...[
              KnowledgeView(
                knowledge: knowledge,
                itemId: knowledge.item.id,
                personNamesById: _personNamesById,
                persons: _persons,
                assignEnabled: !_saving,
                cropIntents: _cropIntents,
                appearanceIntents: _appearanceIntents,
                exclusionIntents: _exclusionIntents,
                pendingItemAssigns: _pendingItemAssigns,
                onPersonTap: _openPerson,
                onAssignCrop: _assignCrop,
                onAssignItem: _assignItem,
                onReassignAppearance: _reassignAppearance,
                onUnassign: _unassignAppearance,
                onExcludeCrop: _excludeCrop,
                onAssignIncludedExclusion: _assignIncludedExclusion,
                onExcludeIncludedExclusion: _excludeIncludedExclusion,
                onRemovePendingItemAssign: (index) {
                  _mutateDraft(
                    () => _pendingItemAssigns.removeAt(index),
                    label: 'Unassign',
                  );
                },
              ),
              Builder(
                builder: (context) {
                  final includedIds = {
                    for (final e in _exclusionIntents.entries)
                      if (e.value.include) e.key,
                  };
                  final draftExcluded = [
                    for (final tag in whoFaceCropTags(knowledge))
                      if (_cropIntents[tag.id]?.exclude == true) tag,
                  ];
                  final visibleSaved = knowledge.whoExclusions
                      .where((e) => !includedIds.contains(e.id));
                  if (visibleSaved.isEmpty && draftExcluded.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      ExcludedFacesStrip(
                        knowledge: knowledge,
                        draftExcludedCrops: draftExcluded,
                        includedExclusionIds: includedIds,
                        onIncludeExclusion: _includeExclusion,
                        onIncludeDraftCrop: _includeDraftCrop,
                        includeEnabled: !_saving,
                      ),
                    ],
                  );
                },
              ),
            ],
            UndoDepthBadge(controller: _undoStack),
            const SizedBox(height: 12),
            if (review.phase == ReviewPhase.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: CircularProgressIndicator(
                    key: Key('review-loading'),
                  ),
                ),
              )
            else if (review.phase == ReviewPhase.error)
              _ReviewError(
                error: review.error!,
                onRetry: () => review.load(),
              )
            else if (knowledge != null && media != null) ...[
              if (media.status != LocalMediaStatus.available) ...[
                _MediaStatusBanner(resolution: media),
                const SizedBox(height: 12),
              ],
              MediaViewer(
                itemType: knowledge.item.type,
                resolution: media,
                player: _player,
                videoController: _videoController,
                whoOverlays: showFaceOverlays
                    ? knowledge.tags
                        .where(
                          (t) =>
                              t.dimension == 'who' &&
                              t.status == TagStatus.active &&
                              t.region != null,
                        )
                        .toList()
                    : const [],
              ),
              if (_assignError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _assignError!,
                  key: const Key('item-assign-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (review.mutationError != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${review.mutationError}',
                  key: const Key('correction-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              if (knowledge.item.type == ItemType.video) ...[
                const SizedBox(height: 16),
                KeyPeriodScrubber(
                  keyPeriods: knowledge.keyPeriods,
                  player: _player,
                  onEditBounds: (p) => _editBounds(review, p),
                  commentsFor: review.commentsForKeyPeriod,
                  onAddComment: review.addKeyPeriodComment,
                  onEditComment: review.editComment,
                  onDeleteComment: review.deleteComment,
                  correctionsEnabled: !review.isBusy,
                ),
              ],
            ],
          ],
        ),
        ),
        );
      },
    );
  }
}

enum _ItemDetailLeaveChoice { save, discard, cancel }

class _ReviewError extends StatelessWidget {
  const _ReviewError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isNotFound =
        error is ApiException && (error as ApiException).statusCode == 404;
    return Column(
      children: [
        Text(
          isNotFound
              ? 'Knowledge not found'
              : 'Could not load knowledge: $error',
          key: isNotFound
              ? const Key('review-not-found')
              : const Key('review-error'),
          textAlign: TextAlign.center,
        ),
        if (!isNotFound) ...[
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('review-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ],
    );
  }
}

class _MediaStatusBanner extends StatelessWidget {
  const _MediaStatusBanner({required this.resolution});

  final LocalMediaResolution resolution;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Key key;
    switch (resolution.status) {
      case LocalMediaStatus.available:
        return const SizedBox.shrink();
      case LocalMediaStatus.missing:
        label = 'Local media missing.';
        key = const Key('media-status-missing');
      case LocalMediaStatus.accessDenied:
        label =
            'Local media access denied (macOS sandbox). Re-select the folder.';
        key = const Key('media-status-access-denied');
      case LocalMediaStatus.hashMismatch:
        label = 'This file does not match the library record.';
        key = const Key('media-status-hash-mismatch');
      case LocalMediaStatus.unsupported:
        label = 'Local media not supported for this source.';
        key = const Key('media-status-unsupported');
    }
    return Text(label, key: key);
  }
}
