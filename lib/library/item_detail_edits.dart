import 'package:flutter/foundation.dart';

/// One intended person change on item detail (not written until Save).
class PersonAssignIntent {
  const PersonAssignIntent({
    this.personId,
    this.name,
    this.unassign = false,
    this.exclude = false,
    this.include = false,
  });

  final String? personId;
  final String? name;
  final bool unassign;
  final bool exclude;
  final bool include;

  bool get hasTarget =>
      !unassign &&
      !exclude &&
      ((personId != null && personId!.isNotEmpty) ||
          (name != null && name!.trim().isNotEmpty));

  bool sameAs(PersonAssignIntent other) {
    return personId == other.personId &&
        name == other.name &&
        unassign == other.unassign &&
        exclude == other.exclude &&
        include == other.include;
  }
}

/// Dirty flag + Save/Discard hooks so the item AppBar / back gate can
/// commit drafts owned by [ItemReviewSection].
class ItemDetailEdits extends ChangeNotifier {
  bool _dirty = false;
  bool _saving = false;

  Future<void> Function()? save;
  VoidCallback? discard;
  Future<bool> Function()? confirmLeave;

  bool get isDirty => _dirty;
  bool get saving => _saving;

  void update({bool? dirty, bool? saving}) {
    var changed = false;
    if (dirty != null && dirty != _dirty) {
      _dirty = dirty;
      changed = true;
    }
    if (saving != null && saving != _saving) {
      _saving = saving;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
