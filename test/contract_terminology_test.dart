// D0 regression — R2 terminology parity.
//
// Every schema in the shared @tagkin/contract OpenAPI must appear as a generated
// Dart type with the SAME name, and no forbidden synonym may leak in as a domain
// type. This is the client-side half of the terminology lock (Rules R2).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const List<String> _openApiCandidates = <String>[
  'openapi/openapi.yaml',
  // Local monorepo sibling (mac/win scripts).
  '../TagKin/packages/contract/openapi/openapi.yaml',
  // CI: actions/checkout path: TagKin under GITHUB_WORKSPACE.
  'TagKin/packages/contract/openapi/openapi.yaml',
];

// Synonyms that must never be used for canonical domain concepts (R2).
const Set<String> _forbiddenTypeNames = <String>{
  'Annotation',
  'Asset',
  'MediaObject',
  'Chapter',
  'KeyPoint',
  'Label',
  'IndexEntry',
};

// Canonical domain terms that must exist as generated types.
const Set<String> _canonicalTypes = <String>{
  'Item',
  'Tag',
  'Person',
  'KeyPeriod',
  'Comment',
};

String _resolveSpecPath() {
  final override = Platform.environment['TAGKIN_OPENAPI'];
  if (override != null && File(override).existsSync()) return override;
  for (final c in _openApiCandidates) {
    if (File(c).existsSync()) return c;
  }
  throw StateError('OpenAPI contract not found; tried $_openApiCandidates');
}

void main() {
  final generated = File('lib/contract/contract.dart');
  final source = generated.readAsStringSync();

  // Names declared as a class/enum in the generated file.
  final declared = RegExp(r'^(?:class|enum)\s+(\w+)', multiLine: true)
      .allMatches(source)
      .map((m) => m.group(1)!)
      .toSet();

  final schemas =
      ((loadYaml(File(_resolveSpecPath()).readAsStringSync()) as YamlMap)['components']
          as YamlMap)['schemas'] as YamlMap;
  final schemaNames = schemas.keys.map((k) => k.toString()).toSet();

  test('generated Dart file exists and declares types', () {
    expect(generated.existsSync(), isTrue,
        reason: 'run tool/gen_contract.dart (mac/102_codegen.sh)');
    expect(declared, isNotEmpty);
  });

  test('every contract schema is generated with the same name (R2)', () {
    final missing = schemaNames.difference(declared);
    expect(missing, isEmpty,
        reason: 'schemas missing from generated Dart: $missing');
  });

  test('canonical domain terms are present as generated types (R2)', () {
    final missing = _canonicalTypes.difference(declared);
    expect(missing, isEmpty, reason: 'missing canonical types: $missing');
  });

  test('no forbidden synonym is used as a domain type (R2)', () {
    final leaked = declared.intersection(_forbiddenTypeNames);
    expect(leaked, isEmpty, reason: 'forbidden synonym types present: $leaked');
  });

  // Inline object-with-properties must become a typed class, not Map (R3 fidelity).
  // UndoCorrectionResult.restored is the known case in the current contract.
  test('inline object schemas synthesize typed classes (not Map)', () {
    expect(declared, contains('UndoCorrectionResultRestored'));
    expect(
      source.contains('final Map<String, dynamic> restored'),
      isFalse,
      reason: 'UndoCorrectionResult.restored must not degrade to Map',
    );
    expect(
      source.contains('final UndoCorrectionResultRestored restored'),
      isTrue,
    );
  });
}
