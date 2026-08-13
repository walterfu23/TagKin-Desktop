import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Request to focus the (already-mounted) Faces trays on a person / folder.
///
/// Written by [openFaceCropTrays]; consumed by [FaceCropTraysPage] via
/// [faceCropFocusRequestProvider]. [nonce] makes repeated identical focuses
/// distinguishable so the listener always fires.
class FaceCropFocusRequest {
  const FaceCropFocusRequest({
    this.personId,
    this.leafFolder,
    required this.nonce,
  });

  final String? personId;
  final String? leafFolder;
  final int nonce;
}

int faceCropFocusNonce = 0;

/// Pending focus for the Faces tab (null when idle).
final faceCropFocusRequestProvider = StateProvider<FaceCropFocusRequest?>(
  (ref) => null,
);

/// Registered by [FaceCropTraysPage] while mounted; invoked by AppShell Cmd+A
/// when the Faces tab is active (focus-independent).
VoidCallback? facesSelectAllLooseHandler;
