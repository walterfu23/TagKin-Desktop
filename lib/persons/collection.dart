/// A named saved set of leaf folders (local-only catalog entry).
///
/// [id] is the collection GUID (UUID v4 for newly minted collections).
///
/// Collections are not owned by the server. Persons stay account-scoped;
/// a collection only scopes which folders the Faces dropdown shows.
///
/// Under development — not shipped.
class Collection {
  const Collection({
    required this.id,
    required this.name,
    required this.leafFolders,
    this.ui = CollectionUiState.empty,
  });

  /// Collection GUID persisted in collections.json.
  final String id;
  final String name;

  /// Normalized absolute leaf folder paths.
  final List<String> leafFolders;

  /// Folders / Faces page look (not Settings — those stay app-global).
  final CollectionUiState ui;

  Collection copyWith({
    String? id,
    String? name,
    List<String>? leafFolders,
    CollectionUiState? ui,
  }) {
    return Collection(
      id: id ?? this.id,
      name: name ?? this.name,
      leafFolders: leafFolders ?? this.leafFolders,
      ui: ui ?? this.ui,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'leafFolders': leafFolders,
        if (ui != CollectionUiState.empty) 'ui': ui.toJson(),
      };

  factory Collection.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final folders = json['leafFolders'];
    final uiRaw = json['ui'];
    return Collection(
      id: id is String ? id : '',
      name: name is String ? name : '',
      leafFolders: folders is List
          ? [
              for (final f in folders)
                if (f is String && f.isNotEmpty) f,
            ]
          : const [],
      ui: uiRaw is Map
          ? CollectionUiState.fromJson(
              uiRaw.map((k, v) => MapEntry(k.toString(), v)),
            )
          : CollectionUiState.empty,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Collection &&
      other.id == id &&
      other.name == name &&
      _listEquals(other.leafFolders, leafFolders) &&
      other.ui == ui;

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAll(leafFolders), ui);
}

/// Persisted page look for one collection (Folders + Faces only).
class CollectionUiState {
  const CollectionUiState({
    this.library = const CollectionLibraryUi(),
    this.faces = const CollectionFacesUi(),
  });

  final CollectionLibraryUi library;
  final CollectionFacesUi faces;

  static const empty = CollectionUiState();

  CollectionUiState copyWith({
    CollectionLibraryUi? library,
    CollectionFacesUi? faces,
  }) {
    return CollectionUiState(
      library: library ?? this.library,
      faces: faces ?? this.faces,
    );
  }

  Map<String, Object?> toJson() => {
        if (library != const CollectionLibraryUi()) 'library': library.toJson(),
        if (faces != const CollectionFacesUi()) 'faces': faces.toJson(),
      };

  factory CollectionUiState.fromJson(Map<String, dynamic> json) {
    final lib = json['library'];
    final faces = json['faces'];
    return CollectionUiState(
      library: lib is Map
          ? CollectionLibraryUi.fromJson(
              lib.map((k, v) => MapEntry(k.toString(), v)),
            )
          : const CollectionLibraryUi(),
      faces: faces is Map
          ? CollectionFacesUi.fromJson(
              faces.map((k, v) => MapEntry(k.toString(), v)),
            )
          : const CollectionFacesUi(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CollectionUiState &&
      other.library == library &&
      other.faces == faces;

  @override
  int get hashCode => Object.hash(library, faces);
}

class CollectionLibraryUi {
  const CollectionLibraryUi({
    this.filterQuery = '',
    this.statusFilter,
    this.sortKeys = const [],
    this.expandedDirs = const [],
  });

  final String filterQuery;

  /// [ProcessingStatus.wire] value, or null for all.
  final String? statusFilter;

  final List<CollectionSortKey> sortKeys;
  final List<String> expandedDirs;

  CollectionLibraryUi copyWith({
    String? filterQuery,
    String? statusFilter,
    bool clearStatusFilter = false,
    List<CollectionSortKey>? sortKeys,
    List<String>? expandedDirs,
  }) {
    return CollectionLibraryUi(
      filterQuery: filterQuery ?? this.filterQuery,
      statusFilter:
          clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      sortKeys: sortKeys ?? this.sortKeys,
      expandedDirs: expandedDirs ?? this.expandedDirs,
    );
  }

  Map<String, Object?> toJson() => {
        'filterQuery': filterQuery,
        'statusFilter': statusFilter,
        'sortKeys': [for (final k in sortKeys) k.toJson()],
        'expandedDirs': expandedDirs,
      };

  factory CollectionLibraryUi.fromJson(Map<String, dynamic> json) {
    final q = json['filterQuery'];
    final status = json['statusFilter'];
    final keysRaw = json['sortKeys'];
    final dirsRaw = json['expandedDirs'];
    final keys = <CollectionSortKey>[];
    if (keysRaw is List) {
      for (final entry in keysRaw) {
        if (entry is Map) {
          keys.add(
            CollectionSortKey.fromJson(
              entry.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      }
    }
    final dirs = <String>[];
    if (dirsRaw is List) {
      for (final d in dirsRaw) {
        if (d is String && d.isNotEmpty) dirs.add(d);
      }
    }
    return CollectionLibraryUi(
      filterQuery: q is String ? q : '',
      statusFilter: status is String && status.isNotEmpty ? status : null,
      sortKeys: keys,
      expandedDirs: dirs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CollectionLibraryUi &&
      other.filterQuery == filterQuery &&
      other.statusFilter == statusFilter &&
      _listEquals(other.sortKeys, sortKeys) &&
      _listEquals(other.expandedDirs, expandedDirs);

  @override
  int get hashCode => Object.hash(
        filterQuery,
        statusFilter,
        Object.hashAll(sortKeys),
        Object.hashAll(expandedDirs),
      );
}

class CollectionSortKey {
  const CollectionSortKey(this.column, {this.ascending = true});

  final String column;
  final bool ascending;

  Map<String, Object?> toJson() => {
        'column': column,
        'ascending': ascending,
      };

  factory CollectionSortKey.fromJson(Map<String, dynamic> json) {
    final col = json['column'];
    final asc = json['ascending'];
    return CollectionSortKey(
      col is String ? col : 'who',
      ascending: asc is bool ? asc : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CollectionSortKey &&
      other.column == column &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(column, ascending);
}

class CollectionFacesUi {
  const CollectionFacesUi({
    this.leafFolder,
    this.personId,
  });

  final String? leafFolder;
  final String? personId;

  CollectionFacesUi copyWith({
    String? leafFolder,
    String? personId,
    bool clearPersonId = false,
    bool clearLeafFolder = false,
  }) {
    return CollectionFacesUi(
      leafFolder: clearLeafFolder ? null : (leafFolder ?? this.leafFolder),
      personId: clearPersonId ? null : (personId ?? this.personId),
    );
  }

  Map<String, Object?> toJson() => {
        'leafFolder': leafFolder,
        'personId': personId,
      };

  factory CollectionFacesUi.fromJson(Map<String, dynamic> json) {
    final folder = json['leafFolder'];
    final person = json['personId'];
    return CollectionFacesUi(
      leafFolder: folder is String && folder.isNotEmpty ? folder : null,
      personId: person is String && person.isNotEmpty ? person : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CollectionFacesUi &&
      other.leafFolder == leafFolder &&
      other.personId == personId;

  @override
  int get hashCode => Object.hash(leafFolder, personId);
}

/// On-disk catalog of collections, last current id, and recent open order.
class CollectionsFile {
  const CollectionsFile({
    this.collections = const [],
    this.currentCollectionId,
    this.recentCollectionIds = const [],
  });

  final List<Collection> collections;
  final String? currentCollectionId;

  /// Most-recent-first collection ids (capped when written).
  final List<String> recentCollectionIds;

  static const empty = CollectionsFile();
  static const maxRecents = 20;

  CollectionsFile copyWith({
    List<Collection>? collections,
    String? currentCollectionId,
    bool clearCurrent = false,
    List<String>? recentCollectionIds,
  }) {
    return CollectionsFile(
      collections: collections ?? this.collections,
      currentCollectionId: clearCurrent
          ? null
          : (currentCollectionId ?? this.currentCollectionId),
      recentCollectionIds: recentCollectionIds ?? this.recentCollectionIds,
    );
  }

  Map<String, Object?> toJson() => {
        'collections': [for (final c in collections) c.toJson()],
        'currentCollectionId': currentCollectionId,
        'recentCollectionIds': recentCollectionIds,
      };

  factory CollectionsFile.fromJson(Map<String, dynamic> json) {
    final raw = json['collections'];
    final collections = <Collection>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          final c = Collection.fromJson(
            entry.map((k, v) => MapEntry(k.toString(), v)),
          );
          if (c.id.isNotEmpty && c.name.trim().isNotEmpty) {
            collections.add(c);
          }
        }
      }
    }
    final current = json['currentCollectionId'];
    final recentsRaw = json['recentCollectionIds'];
    final recents = <String>[];
    if (recentsRaw is List) {
      for (final id in recentsRaw) {
        if (id is String && id.isNotEmpty && !recents.contains(id)) {
          recents.add(id);
        }
      }
    }
    return CollectionsFile(
      collections: collections,
      currentCollectionId: current is String && current.isNotEmpty
          ? current
          : null,
      recentCollectionIds: recents,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CollectionsFile &&
      other.currentCollectionId == currentCollectionId &&
      _listEquals(other.collections, collections) &&
      _listEquals(other.recentCollectionIds, recentCollectionIds);

  @override
  int get hashCode => Object.hash(
        currentCollectionId,
        Object.hashAll(collections),
        Object.hashAll(recentCollectionIds),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
