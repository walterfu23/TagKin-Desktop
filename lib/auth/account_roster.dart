import 'dart:convert';
import 'dart:io';

import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/provider_session.dart';
import 'package:tagkin_desktop/auth/secure_persistor.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';

/// Secure-store key for every Firebase session on this computer, plus which
/// one is active. Tokens stay here. The email list lives in Application Support.
const String kFirebaseRosterKey = 'tagkin.firebase.roster';

/// An account this computer has set up. No tokens.
class SavedAccount {
  const SavedAccount({
    required this.localId,
    this.email,
    this.hasSession = false,
  });

  final String localId;
  final String? email;

  /// True when the secure store still has this account's session.
  final bool hasSession;

  String get label {
    final value = email?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return localId;
  }

  Map<String, Object?> toJson() => {
    'localId': localId,
    if (email != null && email!.isNotEmpty) 'email': email,
  };

  static SavedAccount? tryParse(Object? json) {
    if (json is! Map) return null;
    final localId = json['localId'];
    if (localId is! String || localId.isEmpty) return null;
    final email = json['email'];
    return SavedAccount(
      localId: localId,
      email: email is String && email.isNotEmpty ? email : null,
    );
  }
}

/// Non-secret account list. Survives a wiped Keychain or Credential Manager.
abstract class AccountDirectory {
  Future<List<SavedAccount>> read();
  Future<void> upsert(SavedAccount account);
  Future<void> remove(String localId);
  Future<void> clear();
}

class MemoryAccountDirectory implements AccountDirectory {
  final List<SavedAccount> _accounts = [];

  @override
  Future<List<SavedAccount>> read() async => List<SavedAccount>.of(_accounts);

  @override
  Future<void> upsert(SavedAccount account) async {
    SavedAccount? existing;
    for (final saved in _accounts) {
      if (saved.localId == account.localId) existing = saved;
    }
    _accounts.removeWhere((a) => a.localId == account.localId);
    _accounts.add(
      SavedAccount(
        localId: account.localId,
        email: account.email ?? existing?.email,
      ),
    );
  }

  @override
  Future<void> remove(String localId) async {
    _accounts.removeWhere((a) => a.localId == localId);
  }

  @override
  Future<void> clear() async {
    _accounts.clear();
  }
}

class FileAccountDirectory implements AccountDirectory {
  FileAccountDirectory({this.supportDir});

  final Directory? supportDir;

  Future<File> _file() async {
    final dir = await tagkinAppSupportDir(override: supportDir);
    return File('${dir.path}/accounts.json');
  }

  @override
  Future<List<SavedAccount>> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];
      final raw = decoded['accounts'];
      if (raw is! List) return const [];
      return [for (final entry in raw) ?SavedAccount.tryParse(entry)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<SavedAccount> accounts) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode({
        'accounts': [for (final account in accounts) account.toJson()],
      }),
    );
  }

  @override
  Future<void> upsert(SavedAccount account) async {
    final accounts = await read();
    String? email = account.email;
    for (final existing in accounts) {
      if (existing.localId == account.localId && email == null) {
        email = existing.email;
      }
    }
    final next = [
      for (final existing in accounts)
        if (existing.localId != account.localId) existing,
      SavedAccount(localId: account.localId, email: email),
    ];
    await _write(next);
  }

  @override
  Future<void> remove(String localId) async {
    final accounts = await read();
    await _write([
      for (final account in accounts)
        if (account.localId != localId) account,
    ]);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }
}

class _RosterBlob {
  const _RosterBlob({required this.activeLocalId, required this.sessions});

  final String? activeLocalId;
  final Map<String, FirebaseSession> sessions;

  static const empty = _RosterBlob(activeLocalId: null, sessions: {});
}

/// Firebase sessions in the OS secure store, plus the non-secret directory.
class FirebaseAccountRoster {
  FirebaseAccountRoster({required this.secure, required this.directory});

  final SecureKeyValueStore secure;
  final AccountDirectory directory;

  Future<_RosterBlob> _readBlob() async {
    final raw = await secure.read(key: kFirebaseRosterKey);
    if (raw == null || raw.isEmpty) return _RosterBlob.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _RosterBlob.empty;
      final active = decoded['activeLocalId'];
      final sessionsRaw = decoded['sessions'];
      final sessions = <String, FirebaseSession>{};
      if (sessionsRaw is Map) {
        for (final entry in sessionsRaw.entries) {
          final session = FirebaseSession.tryParse(entry.value);
          if (session == null) continue;
          sessions[session.localId] = session;
        }
      }
      return _RosterBlob(
        activeLocalId: active is String && active.isNotEmpty ? active : null,
        sessions: sessions,
      );
    } on FormatException {
      return _RosterBlob.empty;
    }
  }

  Future<void> _writeBlob(_RosterBlob blob) async {
    if (blob.sessions.isEmpty) {
      await secure.delete(key: kFirebaseRosterKey);
      return;
    }
    await secure.write(
      key: kFirebaseRosterKey,
      value: jsonEncode({
        'activeLocalId': blob.activeLocalId,
        'sessions': {
          for (final session in blob.sessions.values)
            session.localId: session.toJson(),
        },
      }),
    );
  }

  /// Copies a valid pre-roster session into the roster without making it
  /// active, so the account list can open Folders on a tap.
  Future<void> _adoptLegacy() async {
    final raw = await secure.read(key: kFirebaseSessionKey);
    if (raw == null || raw.isEmpty) return;
    FirebaseSession? legacy;
    try {
      legacy = FirebaseSession.tryParse(jsonDecode(raw));
    } on FormatException {
      return;
    }
    if (legacy == null) return;
    final blob = await _readBlob();
    if (blob.sessions.containsKey(legacy.localId)) return;
    for (final session in blob.sessions.values) {
      if (_sameEmail(session.email, legacy.email)) return;
    }
    final sessions = Map<String, FirebaseSession>.of(blob.sessions);
    sessions[legacy.localId] = legacy;
    await _writeBlob(
      _RosterBlob(activeLocalId: blob.activeLocalId, sessions: sessions),
    );
    await directory.upsert(
      SavedAccount(localId: legacy.localId, email: legacy.email),
    );
  }

  Future<List<SavedAccount>> accounts() async {
    await _adoptLegacy();
    final blob = await _readBlob();
    final listed = await directory.read();
    final byId = <String, SavedAccount>{
      for (final account in listed) account.localId: account,
    };
    for (final session in blob.sessions.values) {
      final existing = byId[session.localId];
      byId[session.localId] = SavedAccount(
        localId: session.localId,
        email: session.email ?? existing?.email,
        hasSession: true,
      );
    }
    final merged = <SavedAccount>[];
    final emitted = <String>{};
    for (final account in listed) {
      final session = _sessionFor(account, blob.sessions);
      final id = session?.localId ?? account.localId;
      if (!emitted.add(id)) continue;
      merged.add(
        SavedAccount(
          localId: id,
          email: session?.email ?? account.email,
          hasSession: session != null,
        ),
      );
      byId.remove(account.localId);
      if (session != null) byId.remove(session.localId);
    }
    for (final extra in byId.values) {
      if (!emitted.add(extra.localId)) continue;
      merged.add(extra);
    }
    return merged;
  }

  FirebaseSession? _sessionFor(
    SavedAccount account,
    Map<String, FirebaseSession> sessions,
  ) {
    final direct = sessions[account.localId];
    if (direct != null) return direct;
    for (final session in sessions.values) {
      if (_sameEmail(session.email, account.email)) return session;
    }
    return null;
  }

  Future<FirebaseSession?> activeSession() async {
    final blob = await _readBlob();
    final id = blob.activeLocalId;
    if (id == null) return null;
    return blob.sessions[id];
  }

  Future<FirebaseSession?> sessionFor(String localId) async {
    final blob = await _readBlob();
    return blob.sessions[localId];
  }

  /// Saves [session], makes it active, and records it in the directory.
  Future<void> remember(FirebaseSession session) async {
    final blob = await _readBlob();
    final sessions = Map<String, FirebaseSession>.of(blob.sessions);
    sessions[session.localId] = session;
    await _writeBlob(
      _RosterBlob(activeLocalId: session.localId, sessions: sessions),
    );
    await directory.upsert(
      SavedAccount(localId: session.localId, email: session.email),
    );
  }

  /// Makes a stored session active. Returns null when that session is gone.
  Future<FirebaseSession?> makeActive(String localId) async {
    final blob = await _readBlob();
    final session = blob.sessions[localId];
    if (session == null) return null;
    await _writeBlob(
      _RosterBlob(activeLocalId: localId, sessions: blob.sessions),
    );
    return session;
  }

  /// Drops the secure session after the server rejects it. The directory
  /// entry stays so setup can prefill the email.
  Future<void> dropSession(String localId) async {
    final blob = await _readBlob();
    final sessions = Map<String, FirebaseSession>.of(blob.sessions);
    sessions.remove(localId);
    final active = blob.activeLocalId == localId ? null : blob.activeLocalId;
    await _writeBlob(_RosterBlob(activeLocalId: active, sessions: sessions));
    await _dropLegacyIf(localId);
  }

  /// Removes the account from this computer. Does not revoke it on the server.
  /// Returns the session that should become active, if any.
  Future<FirebaseSession?> removeFromComputer(String localId) async {
    final blob = await _readBlob();
    final sessions = Map<String, FirebaseSession>.of(blob.sessions);
    sessions.remove(localId);
    await directory.remove(localId);
    String? active = blob.activeLocalId;
    if (active == localId) {
      active = sessions.isEmpty ? null : sessions.keys.first;
    }
    await _writeBlob(_RosterBlob(activeLocalId: active, sessions: sessions));
    if (active == null) return null;
    return sessions[active];
  }

  Future<void> clear() async {
    await secure.delete(key: kFirebaseRosterKey);
    await secure.delete(key: kFirebaseSessionKey);
    await secure.delete(key: kFirebaseGateKey);
    await directory.clear();
  }

  Future<void> _dropLegacyIf(String localId) async {
    final raw = await secure.read(key: kFirebaseSessionKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final legacy = FirebaseSession.tryParse(jsonDecode(raw));
      if (legacy?.localId == localId) {
        await secure.delete(key: kFirebaseSessionKey);
      }
    } on FormatException {
      await secure.delete(key: kFirebaseSessionKey);
    }
  }
}

bool _sameEmail(String? a, String? b) {
  final left = a?.trim().toLowerCase() ?? '';
  final right = b?.trim().toLowerCase() ?? '';
  return left.isNotEmpty && left == right;
}
