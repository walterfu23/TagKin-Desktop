// Regenerates user-facing name + icon artifacts from branding/.
//
// Single source of truth: branding/branding.yaml + branding/icon_macos.png
// and branding/icon_windows.png. Internal ids (package name, bundle id,
// OAuth scheme) are not touched.
//
// Run: dart run tool/gen_branding.dart
//      dart run tool/gen_branding.dart --check
//      dart run tool/gen_branding.dart --admin

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:yaml/yaml.dart';

const List<int> _macIconSizes = <int>[16, 32, 64, 128, 256, 512, 1024];
const List<int> _winIcoSizes = <int>[16, 24, 32, 48, 64, 128, 256];

final _fileNameRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');

class _Branding {
  _Branding({
    required this.appName,
    required this.fileName,
    required this.adminAppName,
  });

  final String appName;
  final String fileName;
  final String adminAppName;

  String get adminFileName => '$fileName-admin';
}

class _Emitter {
  _Emitter({required this.check});

  final bool check;
  var failed = false;
  var wrote = 0;

  void text(File file, String content) {
    final next = content.endsWith('\n') ? content : '$content\n';
    if (check) {
      if (!file.existsSync()) {
        stderr.writeln('error: missing ${file.path}');
        failed = true;
        return;
      }
      if (file.readAsStringSync() != next) {
        stderr.writeln('error: drifted ${file.path}');
        failed = true;
      }
      return;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(next);
    wrote++;
    stdout.writeln('wrote ${file.path}');
  }

  void bytes(File file, Uint8List data) {
    if (check) return;
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data);
    wrote++;
    stdout.writeln('wrote ${file.path}');
  }

  void assertPngSize(File file, int size) {
    if (!check) return;
    if (!file.existsSync()) {
      stderr.writeln('error: missing ${file.path}');
      failed = true;
      return;
    }
    final decoded = img.decodePng(file.readAsBytesSync());
    if (decoded == null || decoded.width != size || decoded.height != size) {
      stderr.writeln(
        'error: ${file.path} must be ${size}x$size '
        '(got ${decoded?.width}x${decoded?.height})',
      );
      failed = true;
    }
  }

  void assertIcoExists(File file) {
    if (!check) return;
    if (!file.existsSync() || file.lengthSync() < 64) {
      stderr.writeln('error: missing or empty ${file.path}');
      failed = true;
    }
  }
}

void main(List<String> args) {
  final check = args.contains('--check');
  final admin = args.contains('--admin');
  final root = Directory.current;
  final brandingDir = Directory('branding');
  if (!brandingDir.existsSync()) {
    stderr.writeln('error: branding/ not found (run from TagKin-Desktop root)');
    exit(1);
  }

  final spec = _loadBranding(File('branding/branding.yaml'));
  final emitter = _Emitter(check: check);

  if (admin) {
    _emitAdmin(root: root, spec: spec, emitter: emitter);
  } else {
    _emitDesktop(root: root, spec: spec, emitter: emitter);
  }

  if (check) {
    if (emitter.failed) {
      stderr.writeln(
        'error: branding artifacts drifted — run '
        '${admin ? 'TagKin/mac/131_branding-admin.sh' : 'mac/120_branding.sh · win/120_branding.ps1'}',
      );
      exit(1);
    }
    stdout.writeln('branding check ok');
    return;
  }
  stdout.writeln('branding generated (${emitter.wrote} files)');
}

_Branding _loadBranding(File yamlFile) {
  if (!yamlFile.existsSync()) {
    stderr.writeln('error: missing ${yamlFile.path}');
    exit(1);
  }
  final doc = loadYaml(yamlFile.readAsStringSync());
  if (doc is! YamlMap) {
    stderr.writeln('error: ${yamlFile.path} must be a mapping');
    exit(1);
  }
  final appName = (doc['appName'] ?? '').toString().trim();
  if (appName.isEmpty) {
    stderr.writeln('error: branding.yaml appName is required');
    exit(1);
  }
  var fileName = (doc['fileName'] ?? '').toString().trim();
  if (fileName.isEmpty) {
    fileName = appName.replaceAll(RegExp(r'\s+'), '');
  }
  if (!_fileNameRe.hasMatch(fileName)) {
    stderr.writeln(
      'error: fileName "$fileName" must be letters, digits, hyphen, underscore',
    );
    exit(1);
  }
  var adminAppName = (doc['adminAppName'] ?? '').toString().trim();
  if (adminAppName.isEmpty) {
    adminAppName = '$appName Admin';
  }
  return _Branding(
    appName: appName,
    fileName: fileName,
    adminAppName: adminAppName,
  );
}

void _emitDesktop({
  required Directory root,
  required _Branding spec,
  required _Emitter emitter,
}) {
  emitter.text(File('lib/branding.g.dart'), _dartDesktop(spec));
  emitter.text(
    File('macos/Runner/Configs/Branding.xcconfig'),
    _xcconfig(productName: spec.fileName, displayName: spec.appName),
  );
  emitter.text(File('windows/runner/branding.g.h'), _winHeader(spec));
  emitter.text(
    File('windows/runner/branding.g.cmake'),
    '# GENERATED — do not edit by hand.\n'
    '# dart run tool/gen_branding.dart\n'
    'set(BINARY_NAME "${spec.fileName}")\n',
  );

  final macSrc = _decodePng(File('branding/icon_macos.png'), minSize: 1024);
  final winSrc = _decodePng(File('branding/icon_windows.png'), minSize: 256);
  final appiconset = Directory(
    'macos/Runner/Assets.xcassets/AppIcon.appiconset',
  );
  for (final size in _macIconSizes) {
    final out = File('${appiconset.path}/app_icon_$size.png');
    emitter.bytes(out, _pngAt(macSrc, size));
    emitter.assertPngSize(out, size);
  }
  final ico = File('windows/runner/resources/app_icon.ico');
  emitter.bytes(ico, _encodeIco(winSrc, _winIcoSizes));
  emitter.assertIcoExists(ico);

  _syncMacosBundleName(
    pbxproj: File('macos/Runner.xcodeproj/project.pbxproj'),
    scheme: File(
      'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    ),
    fileName: spec.fileName,
    emitter: emitter,
  );
}

void _emitAdmin({
  required Directory root,
  required _Branding spec,
  required _Emitter emitter,
}) {
  final adminRoot = _resolveAdminRoot();
  if (adminRoot == null) {
    stderr.writeln(
      'error: admin-tool not found (set TAGKIN_ADMIN_TOOL or keep '
      'TagKin/admin-tool next to TagKin-Desktop)',
    );
    exit(1);
  }
  stdout.writeln('==> admin-tool ${adminRoot.path}');

  emitter.text(File('${adminRoot.path}/lib/branding.g.dart'), _dartAdmin(spec));
  emitter.text(
    File('${adminRoot.path}/macos/Runner/Configs/Branding.xcconfig'),
    _xcconfig(productName: spec.adminFileName, displayName: spec.adminAppName),
  );

  final adminIcon = File('branding/icon_macos_admin.png');
  final srcFile = adminIcon.existsSync()
      ? adminIcon
      : File('branding/icon_macos.png');
  final macSrc = _decodePng(srcFile, minSize: 1024);
  final appiconset = Directory(
    '${adminRoot.path}/macos/Runner/Assets.xcassets/AppIcon.appiconset',
  );
  for (final size in _macIconSizes) {
    final out = File('${appiconset.path}/app_icon_$size.png');
    emitter.bytes(out, _pngAt(macSrc, size));
    emitter.assertPngSize(out, size);
  }

  _syncMacosBundleName(
    pbxproj: File('${adminRoot.path}/macos/Runner.xcodeproj/project.pbxproj'),
    scheme: File(
      '${adminRoot.path}/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    ),
    fileName: spec.adminFileName,
    emitter: emitter,
  );
}

Directory? _resolveAdminRoot() {
  final env = Platform.environment['TAGKIN_ADMIN_TOOL'];
  if (env != null && env.isNotEmpty) {
    final d = Directory(env);
    if (d.existsSync()) return d;
    stderr.writeln('error: TAGKIN_ADMIN_TOOL does not exist: $env');
    exit(1);
  }
  final sibling = Directory('../TagKin/admin-tool');
  if (sibling.existsSync()) return sibling;
  return null;
}

void _syncMacosBundleName({
  required File pbxproj,
  required File scheme,
  required String fileName,
  required _Emitter emitter,
}) {
  final bundle = '$fileName.app';
  final quoted = _needsPbxQuotes(bundle) ? '"$bundle"' : bundle;

  if (scheme.existsSync()) {
    final next = scheme.readAsStringSync().replaceAllMapped(
      RegExp(r'BuildableName = "[^"]+\.app"'),
      (_) => 'BuildableName = "$bundle"',
    );
    emitter.text(scheme, next.endsWith('\n') ? next : '$next\n');
  }

  if (!pbxproj.existsSync()) return;
  var s = pbxproj.readAsStringSync();
  s = s.replaceAllMapped(
    RegExp(r'/\* [A-Za-z0-9_.-]+\.app \*/'),
    (_) => '/* $bundle */',
  );
  s = s.replaceAllMapped(
    RegExp(r'path = "?[A-Za-z0-9_.-]+\.app"?'),
    (_) => 'path = $quoted',
  );
  emitter.text(pbxproj, s.endsWith('\n') ? s : '$s\n');
}

bool _needsPbxQuotes(String name) =>
    !RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(name);

img.Image _decodePng(File file, {required int minSize}) {
  if (!file.existsSync()) {
    stderr.writeln('error: missing ${file.path}');
    exit(1);
  }
  final decoded = img.decodePng(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('error: not a PNG: ${file.path}');
    exit(1);
  }
  if (decoded.width < minSize || decoded.height < minSize) {
    stderr.writeln(
      'error: ${file.path} must be at least ${minSize}x$minSize '
      '(got ${decoded.width}x${decoded.height})',
    );
    exit(1);
  }
  return decoded;
}

Uint8List _pngAt(img.Image source, int size) {
  final resized = img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodePng(resized));
}

Uint8List _encodeIco(img.Image source, List<int> sizes) {
  final frames = <img.Image>[
    for (final size in sizes)
      img.copyResize(
        source,
        width: size,
        height: size,
        interpolation: img.Interpolation.average,
      ),
  ];
  return img.IcoEncoder().encodeImages(frames);
}

String _dartDesktop(_Branding spec) {
  return '''
// GENERATED — do not edit by hand.
// Regenerate via tool/gen_branding.dart (mac/120_branding.sh · win/120_branding.ps1).
// Single source of truth: branding/branding.yaml
// ignore_for_file: type=lint

/// User-facing app name (Dock, menu bar, window title, in-app chrome).
const String kAppName = ${_dq(spec.appName)};

/// On-disk bundle / executable name (no spaces).
const String kAppFileName = ${_dq(spec.fileName)};
''';
}

String _dartAdmin(_Branding spec) {
  return '''
// GENERATED — do not edit by hand.
// Regenerate via dart run tool/gen_branding.dart --admin
// (TagKin/mac/131_branding-admin.sh).
// Single source of truth: TagKin-Desktop/branding/branding.yaml
// ignore_for_file: type=lint

/// Operator-facing window / Dock name.
const String kAdminAppTitle = ${_dq(spec.adminAppName)};

/// On-disk bundle name (no spaces).
const String kAdminFileName = ${_dq(spec.adminFileName)};
''';
}

String _xcconfig({required String productName, required String displayName}) {
  return '''
// GENERATED — do not edit by hand.
// dart run tool/gen_branding.dart
PRODUCT_NAME = $productName
PRODUCT_DISPLAY_NAME = $displayName
''';
}

String _winHeader(_Branding spec) {
  final a = _cEscape(spec.appName);
  final exe = _cEscape('${spec.fileName}.exe');
  return '''
// GENERATED — do not edit by hand.
// dart run tool/gen_branding.dart
#pragma once

#define TAGKIN_APP_NAME_A "$a"
#define TAGKIN_APP_NAME_W L"$a"
#define TAGKIN_APP_EXE_A "$exe"
''';
}

String _dq(String value) => "'${value.replaceAll("'", r"\'")}'";

String _cEscape(String value) =>
    value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
