import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS CI runs discovery probe and built-dylib FFI smoke', () {
    final workflow = File('.github/workflows/macos-ci.yml').readAsStringSync();

    expect(workflow, contains('Core Audio discovery probe'));
    expect(workflow, contains('build/native/macos_device_probe --list'));
    expect(workflow, contains('Built-dylib Dart FFI smoke'));
    expect(workflow, contains('LMM_NATIVE_LIBRARY'));
    expect(workflow, contains('test/native_built_library_smoke_test.dart'));
    expect(
      workflow.indexOf('Core Audio discovery probe'),
      greaterThan(workflow.indexOf('Build and test native debug engine')),
    );
    expect(
      workflow.indexOf('Built-dylib Dart FFI smoke'),
      greaterThan(workflow.indexOf('Core Audio discovery probe')),
    );
  });
}
