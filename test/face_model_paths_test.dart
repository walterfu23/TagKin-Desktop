import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/prepass/onnx_face_embedder.dart';

void main() {
  group('FaceModelPaths.walkUpForAssetsModels', () {
    test('emits assets/models under each parent of a macOS .app executable', () {
      final exe = p.join(
        'repo',
        'TagKin-Desktop',
        'build',
        'macos',
        'Build',
        'Products',
        'Debug',
        'tagkin_desktop.app',
        'Contents',
        'MacOS',
        'tagkin_desktop',
      );
      final paths = FaceModelPaths.walkUpForAssetsModels(
        exe,
        fileName: 'w600k_r50.onnx',
        maxLevels: 12,
      );
      expect(
        paths.any(
          (c) => c.endsWith(
            p.join('TagKin-Desktop', 'assets', 'models', 'w600k_r50.onnx'),
          ),
        ),
        isTrue,
      );
    });
  });

  group('FaceModelPaths.defaultModelCandidates', () {
    test('includes App Support and cwd assets paths', () {
      final candidates = FaceModelPaths.defaultModelCandidates(
        fileName: 'w600k_r50.onnx',
        home: '/Users/test',
        currentDir: '/Users/test/TagKin-Desktop',
        executablePath: '/Users/test/TagKin-Desktop/bin/app',
        maxWalkUp: 4,
      );
      expect(
        candidates,
        contains(
          p.join(
            '/Users/test',
            'Library',
            'Application Support',
            'tagkin',
            'models',
            'w600k_r50.onnx',
          ),
        ),
      );
      expect(
        candidates,
        contains(
          p.join('/Users/test', 'TagKin-Desktop', 'assets', 'models',
              'w600k_r50.onnx'),
        ),
      );
    });

    test('resolve finds a file placed under a walked-up assets/models', () async {
      final root = await Directory.systemTemp.createTemp('face_models_');
      addTearDown(() => root.delete(recursive: true));

      final modelsDir = Directory(p.join(root.path, 'assets', 'models'));
      await modelsDir.create(recursive: true);
      final recog = File(p.join(modelsDir.path, 'w600k_r50.onnx'));
      await recog.writeAsBytes([1, 2, 3]);

      // Fake nested executable under root/build/.../MacOS/app
      final exeDir = Directory(
        p.join(
          root.path,
          'build',
          'macos',
          'Build',
          'Products',
          'Debug',
          'app.app',
          'Contents',
          'MacOS',
        ),
      );
      await exeDir.create(recursive: true);
      final exe = File(p.join(exeDir.path, 'app'));
      await exe.writeAsBytes([0]);

      final candidates = FaceModelPaths.defaultModelCandidates(
        fileName: 'w600k_r50.onnx',
        home: p.join(root.path, 'no-home'),
        currentDir: p.join(root.path, 'no-cwd'),
        executablePath: exe.path,
        maxWalkUp: 12,
      );
      final hit = candidates.where((c) => File(c).existsSync()).toList();
      expect(hit, contains(recog.path));
    });
  });
}
