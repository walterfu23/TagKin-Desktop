import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/ingest/physical_memory.dart';

void main() {
  test('parsePhysicalMemoryBytes reads a positive integer', () {
    expect(parsePhysicalMemoryBytes('17179869184\n'), 17179869184);
    expect(parsePhysicalMemoryBytes(' 4294967296 '), 4294967296);
  });

  test('parsePhysicalMemoryBytes rejects empty and non-positive', () {
    expect(parsePhysicalMemoryBytes(''), isNull);
    expect(parsePhysicalMemoryBytes('0'), isNull);
    expect(parsePhysicalMemoryBytes('-1'), isNull);
    expect(parsePhysicalMemoryBytes('not-a-number'), isNull);
  });

  test('folderIngestMaxParallelJobs is 1 under 8 GiB, else 2', () {
    expect(folderIngestMaxParallelJobs(null), 2);
    expect(
      folderIngestMaxParallelJobs(kFolderIngestLowRamThresholdBytes - 1),
      1,
    );
    expect(folderIngestMaxParallelJobs(kFolderIngestLowRamThresholdBytes), 2);
    expect(folderIngestMaxParallelJobs(16 * 1024 * 1024 * 1024), 2);
  });
}
