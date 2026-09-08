import 'dart:io';

/// Below this physical RAM, folder ingest runs one folder at a time.
const int kFolderIngestLowRamThresholdBytes = 8 * 1024 * 1024 * 1024;

/// Folder ingest parallelism when RAM is unknown or at/above the threshold.
const int kDefaultFolderIngestMaxParallelJobs = 2;

/// Folder ingest parallelism when RAM is under [kFolderIngestLowRamThresholdBytes].
const int kLowRamFolderIngestMaxParallelJobs = 1;

/// 1 folder when [physicalMemoryBytes] is known and under 8 GiB; else 2.
///
/// `null` (probe failed) keeps two — fail open to current behavior.
int folderIngestMaxParallelJobs(int? physicalMemoryBytes) {
  if (physicalMemoryBytes == null) {
    return kDefaultFolderIngestMaxParallelJobs;
  }
  if (physicalMemoryBytes < kFolderIngestLowRamThresholdBytes) {
    return kLowRamFolderIngestMaxParallelJobs;
  }
  return kDefaultFolderIngestMaxParallelJobs;
}

/// Parse `sysctl` / CIM stdout as a positive byte count.
int? parsePhysicalMemoryBytes(String stdout) {
  final trimmed = stdout.trim();
  if (trimmed.isEmpty) return null;
  final n = int.tryParse(trimmed);
  if (n == null || n <= 0) return null;
  return n;
}

/// Skip the OS probe (treat RAM as unknown → two folders). Used by unit tests.
Future<int?> unknownPhysicalMemoryBytes() async => null;

/// Read total physical RAM. `null` on failure, timeout, or unsupported OS.
Future<int?> probePhysicalMemoryBytes() async {
  try {
    if (Platform.isMacOS) {
      final result = await Process.run('sysctl', [
        '-n',
        'hw.memsize',
      ], runInShell: false).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) return null;
      return parsePhysicalMemoryBytes(result.stdout.toString());
    }
    if (Platform.isWindows) {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        '[int64](Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory',
      ], runInShell: false).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return null;
      return parsePhysicalMemoryBytes(result.stdout.toString());
    }
  } on Object {
    return null;
  }
  return null;
}
