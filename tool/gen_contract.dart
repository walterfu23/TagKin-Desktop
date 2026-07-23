// Deterministic Dart model generator for the shared @tagkin/contract OpenAPI.
//
// The OpenAPI document is the single source of truth for domain names and
// shapes (R2). This reads components.schemas and emits immutable Dart models +
// enums to lib/contract/contract.dart. Output is deterministic (schemas sorted
// by name; property order preserved) so a snapshot / git-diff check can gate
// drift (see mac/106_test_d0.sh · win/106_test_d0.ps1).
//
// Inline `type: object` schemas with named `properties` become synthesized
// Dart classes (e.g. UndoCorrectionResult.restored → UndoCorrectionResultRestored)
// rather than degrading to Map<String, dynamic>.
//
// Run: dart run tool/gen_contract.dart

import 'dart:io';

import 'package:yaml/yaml.dart';

const List<String> _openApiCandidates = <String>[
  'openapi/openapi.yaml',
  // Local monorepo sibling (mac/win scripts).
  '../TagKin/packages/contract/openapi/openapi.yaml',
  // CI: actions/checkout path: TagKin under GITHUB_WORKSPACE.
  'TagKin/packages/contract/openapi/openapi.yaml',
];

void main() {
  final specPath = _resolveSpecPath();
  final doc = loadYaml(File(specPath).readAsStringSync()) as YamlMap;
  final schemas = (doc['components'] as YamlMap)['schemas'] as YamlMap;

  // Mutable registry: top-level OpenAPI schemas + synthesized nested object types.
  final registry = <String, YamlMap>{
    for (final k in schemas.keys) k.toString(): schemas[k] as YamlMap,
  };
  final enumNames = <String>{
    for (final e in registry.entries)
      if (_isEnum(e.value)) e.key,
  };

  // Discover inline object-with-properties and register synthesized schemas.
  // Iterate until fixed point so nested-inline objects are also typed.
  var growing = true;
  while (growing) {
    growing = false;
    final snapshot = Map<String, YamlMap>.from(registry);
    for (final entry in snapshot.entries) {
      if (enumNames.contains(entry.key)) continue;
      final added = _collectInlineObjects(
        parentName: entry.key,
        schema: entry.value,
        registry: registry,
        enumNames: enumNames,
      );
      if (added) growing = true;
    }
  }

  final names = registry.keys.toList()..sort();

  final out = StringBuffer()
    ..writeln('// GENERATED — do not edit by hand.')
    ..writeln('// Regenerate via tool/gen_contract.dart '
        '(mac/102_codegen.sh · win/102_codegen.ps1).')
    ..writeln('// Single source of truth: @tagkin/contract OpenAPI (R2).')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln();

  for (final name in names) {
    final schema = registry[name]!;
    if (enumNames.contains(name)) {
      _writeEnum(out, name, schema);
    } else {
      _writeClass(out, name, schema, enumNames, registry);
    }
  }

  final target = File('lib/contract/contract.dart');
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(out.toString());
  stdout.writeln('generated ${target.path} '
      '(${names.length} schemas, ${enumNames.length} enums) from $specPath');
}

String _resolveSpecPath() {
  final override = Platform.environment['TAGKIN_OPENAPI'];
  if (override != null && File(override).existsSync()) return override;
  for (final c in _openApiCandidates) {
    if (File(c).existsSync()) return c;
  }
  stderr.writeln('error: could not locate the @tagkin/contract OpenAPI. '
      'Tried: ${_openApiCandidates.join(", ")}. '
      'Set TAGKIN_OPENAPI to override.');
  exit(1);
}

bool _isEnum(YamlMap schema) =>
    schema['type'] == 'string' && schema['enum'] != null;

bool _isInlineObjectWithProperties(YamlMap node) =>
    node['type'] == 'object' &&
    node.containsKey('properties') &&
    !node.containsKey(r'$ref');

/// Walk [schema]'s properties; register any inline object-with-properties as
/// synthesized named schemas. Returns true if the registry grew.
bool _collectInlineObjects({
  required String parentName,
  required YamlMap schema,
  required Map<String, YamlMap> registry,
  required Set<String> enumNames,
}) {
  final props = schema['properties'] as YamlMap?;
  if (props == null) return false;
  var added = false;
  for (final key in props.keys) {
    final fieldName = key.toString();
    var node = props[key] as YamlMap;
    // Unwrap allOf-singleton wrappers (nullable $ref / inline objects).
    if (node.containsKey('allOf') &&
        (node['allOf'] as YamlList).length == 1) {
      final inner = (node['allOf'] as YamlList).first as YamlMap;
      if (_isInlineObjectWithProperties(inner)) {
        node = inner;
      } else {
        continue;
      }
    }
    if (!_isInlineObjectWithProperties(node)) continue;
    final synthName = _synthesizeName(parentName, fieldName);
    if (!registry.containsKey(synthName)) {
      registry[synthName] = node;
      added = true;
    }
  }
  return added;
}

String _synthesizeName(String parent, String field) {
  if (field.isEmpty) return '${parent}Nested';
  return '$parent${field[0].toUpperCase()}${field.substring(1)}';
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

void _writeEnum(StringBuffer out, String name, YamlMap schema) {
  final values = (schema['enum'] as YamlList).map((e) => e.toString()).toList();
  out.writeln('enum $name {');
  for (var i = 0; i < values.length; i++) {
    final wire = values[i];
    final sep = i == values.length - 1 ? ';' : ',';
    out.writeln("  ${_enumMember(wire)}('$wire')$sep");
  }
  out
    ..writeln()
    ..writeln('  const $name(this.wire);')
    ..writeln()
    ..writeln('  final String wire;')
    ..writeln()
    ..writeln('  static $name fromWire(String value) =>')
    ..writeln('      values.firstWhere((e) => e.wire == value);')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  String toString() => wire;')
    ..writeln('}')
    ..writeln();
}

String _enumMember(String wire) {
  final parts = wire.split(RegExp(r'[_\-\s]+')).where((p) => p.isNotEmpty);
  final b = StringBuffer();
  var first = true;
  for (final p in parts) {
    if (first) {
      b.write(p.toLowerCase());
      first = false;
    } else {
      b.write(p[0].toUpperCase() + p.substring(1).toLowerCase());
    }
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Classes
// ---------------------------------------------------------------------------

void _writeClass(
  StringBuffer out,
  String name,
  YamlMap schema,
  Set<String> enumNames,
  Map<String, YamlMap> registry,
) {
  final props = (schema['properties'] as YamlMap?) ?? YamlMap();
  final required = <String>{
    ...?(schema['required'] as YamlList?)?.map((e) => e.toString()),
  };

  final fields = <_Field>[];
  for (final key in props.keys) {
    final fieldName = key.toString();
    final node = props[key] as YamlMap;
    final type = _resolveType(node, enumNames, parentName: name, fieldName: fieldName);
    final nullable = node['nullable'] == true || !required.contains(fieldName);
    fields.add(_Field(fieldName, type, nullable));
  }

  out.writeln('class $name {');

  // Constructor.
  out.writeln('  const $name({');
  for (final f in fields) {
    out.writeln('    ${f.nullable ? '' : 'required '}this.${f.name},');
  }
  out
    ..writeln('  });')
    ..writeln();

  // Fields.
  for (final f in fields) {
    out.writeln('  final ${f.type.dart}${f.nullable ? '?' : ''} ${f.name};');
  }
  out.writeln();

  // fromJson.
  out
    ..writeln('  factory $name.fromJson(Map<String, dynamic> json) => $name(')
    ..writeAll(fields.map(_fromJsonLine))
    ..writeln('      );')
    ..writeln();

  // toJson — omit null optional fields so clients don't send e.g.
  // `keyPeriodIndex: null`, which some servers treat as present+invalid.
  out
    ..writeln('  Map<String, dynamic> toJson() {')
    ..writeln('    final json = <String, dynamic>{};')
    ..writeAll(fields.map(_toJsonAssignLine))
    ..writeln('    return json;')
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}

String _fromJsonLine(_Field f) {
  final access = "json['${f.name}']";
  final expr = f.nullable
      ? '$access == null ? null : ${_fromExpr(access, f.type)}'
      : _fromExpr(access, f.type);
  return '        ${f.name}: $expr,\n';
}

String _toJsonAssignLine(_Field f) {
  final expr = _toExpr(f.name, f.type, f.nullable);
  if (f.nullable) {
    return "    if (${f.name} != null) json['${f.name}'] = $expr;\n";
  }
  return "    json['${f.name}'] = $expr;\n";
}

String _fromExpr(String access, _Type t) {
  switch (t.kind) {
    case _Kind.str:
      return '$access as String';
    case _Kind.integer:
      return '($access as num).toInt()';
    case _Kind.number:
      return '($access as num).toDouble()';
    case _Kind.boolean:
      return '$access as bool';
    case _Kind.map:
      return '$access as Map<String, dynamic>';
    case _Kind.dyn:
      return access;
    case _Kind.enumType:
      return '${t.dart}.fromWire($access as String)';
    case _Kind.classType:
      return '${t.dart}.fromJson($access as Map<String, dynamic>)';
    case _Kind.list:
      return '($access as List<dynamic>)'
          '.map((e) => ${_fromExpr('e', t.element!)}).toList()';
  }
}

String _toExpr(String ref, _Type t, bool nullable) {
  final q = nullable ? '?' : '';
  switch (t.kind) {
    case _Kind.str:
    case _Kind.integer:
    case _Kind.number:
    case _Kind.boolean:
    case _Kind.map:
    case _Kind.dyn:
      return ref;
    case _Kind.enumType:
      return '$ref$q.wire';
    case _Kind.classType:
      return '$ref$q.toJson()';
    case _Kind.list:
      return '$ref$q.map((e) => ${_elemToExpr('e', t.element!)}).toList()';
  }
}

String _elemToExpr(String ref, _Type t) {
  switch (t.kind) {
    case _Kind.enumType:
      return '$ref.wire';
    case _Kind.classType:
      return '$ref.toJson()';
    default:
      return ref;
  }
}

_Type _resolveType(
  YamlMap node,
  Set<String> enumNames, {
  String? parentName,
  String? fieldName,
}) {
  if (node.containsKey(r'$ref')) {
    final refName = node[r'$ref'].toString().split('/').last;
    return _Type(
      refName,
      enumNames.contains(refName) ? _Kind.enumType : _Kind.classType,
    );
  }
  if (node.containsKey('allOf')) {
    final inner = (node['allOf'] as YamlList).first as YamlMap;
    return _resolveType(
      inner,
      enumNames,
      parentName: parentName,
      fieldName: fieldName,
    );
  }
  switch (node['type']) {
    case 'array':
      final el = _resolveType(node['items'] as YamlMap, enumNames);
      return _Type('List<${el.dart}>', _Kind.list, element: el);
    case 'string':
      return const _Type('String', _Kind.str);
    case 'integer':
      return const _Type('int', _Kind.integer);
    case 'number':
      return const _Type('double', _Kind.number);
    case 'boolean':
      return const _Type('bool', _Kind.boolean);
    case 'object':
      // Named properties → synthesized class (registered in the collect pass).
      if (node.containsKey('properties') &&
          parentName != null &&
          fieldName != null) {
        final synth = _synthesizeName(parentName, fieldName);
        return _Type(synth, _Kind.classType);
      }
      // Bare / free-form object → Map.
      return const _Type('Map<String, dynamic>', _Kind.map);
    default:
      return const _Type('Object', _Kind.dyn);
  }
}

enum _Kind { str, integer, number, boolean, map, dyn, enumType, classType, list }

class _Type {
  const _Type(this.dart, this.kind, {this.element});

  final String dart;
  final _Kind kind;
  final _Type? element;
}

class _Field {
  _Field(this.name, this.type, this.nullable);

  final String name;
  final _Type type;
  final bool nullable;
}
