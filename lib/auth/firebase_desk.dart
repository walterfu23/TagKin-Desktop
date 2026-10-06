import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  final String apiUrl;
  final FirebasePublicConfig config;
  final FirebaseSession session;
  final ValueChanged<FirebaseSession> onSession;
  final Future<void> Function() onSignOut;
}

final firebaseDeskProvider = Provider<FirebaseDesk?>((ref) => null);
