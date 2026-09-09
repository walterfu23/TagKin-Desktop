import 'package:tagkin_desktop/contract/contract.dart';

/// One representative's outcome after folder ingest register (`POST /items`).
class IngestOutcome {
  const IngestOutcome({required this.path, this.item, this.error});

  final String path;
  final Item? item;
  final Object? error;

  bool get succeeded => item != null;
}
