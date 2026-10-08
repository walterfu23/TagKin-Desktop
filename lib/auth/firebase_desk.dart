import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/auth/account_roster.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';

/// The signed-in Firebase desk. Null on Clerk.
class FirebaseDesk {
  const FirebaseDesk({
    required this.apiUrl,
    required this.config,
    required this.session,
    required this.onSession,
    required this.onSignOut,
    this.loadAccounts,
    this.activateAccount,
    this.beginSetup,
    this.removeAccount,
  });

  final String apiUrl;
  final FirebasePublicConfig config;
  final FirebaseSession session;
  final ValueChanged<FirebaseSession> onSession;
  final Future<void> Function() onSignOut;
  final Future<List<SavedAccount>> Function()? loadAccounts;
  final Future<void> Function(String localId)? activateAccount;
  final Future<void> Function(String? email)? beginSetup;
  final Future<void> Function(String localId)? removeAccount;
}

final firebaseDeskProvider = Provider<FirebaseDesk?>((ref) => null);
