import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:isar/isar.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:test_api/src/backend/invoker.dart';

import 'sync_async_helper.dart';

const bool kIsWeb = identical(0, 0.0);

Future<void> qEqualSet<T>(
  QueryBuilder<dynamic, T, QQueryOperations> query,
  Iterable<T> target,
) async {
  final results = (await query.tFindAll()).toList();
  expect(results.toSet(), target.toSet());
}

Future<void> qEqual<T>(
  QueryBuilder<dynamic, T, QQueryOperations> query,
  List<T> target,
) async {
  final results = (await query.tFindAll()).toList();
  await qEqualSync(results, target);
}

Future<void> qEqualSync<T>(List<T> actual, List<T> target) async {
  if (actual is List<double?>) {
    for (var i = 0; i < actual.length; i++) {
      expect(doubleListEquals(actual.cast(), target.cast()), true);
    }
  } else if (actual is List<List<double?>?>) {
    for (var i = 0; i < actual.length; i++) {
      doubleListEquals(
        actual[i] as List<double?>?,
        target[i] as List<double?>?,
      );
    }
  } else {
    expect(actual, target);
  }
}

final testErrors = <String>[];
int testCount = 0;

String _getRustTarget() {
  switch (Abi.current()) {
    case Abi.macosArm64:
      return 'aarch64-apple-darwin';
    case Abi.macosX64:
      return 'x86_64-apple-darwin';
    case Abi.linuxArm64:
      return 'aarch64-unknown-linux-gnu';
    case Abi.linuxX64:
      return 'x86_64-unknown-linux-gnu';
    case Abi.windowsX64:
      return 'x86_64-pc-windows-gnu';
    case Abi.windowsIA32:
      return 'i686-pc-windows-gnu';
    default:
      throw UnsupportedError('Unsupported ABI: ${Abi.current()}');
  }
}

var _setUp = false;
Future<void> _prepareTest() async {
  if (!kIsWeb && !_setUp) {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      try {
        final packagesDir = path.dirname(Directory.current.absolute.path);
        final target = _getRustTarget();
        Process.runSync(
          'cargo',
          ['build', '--target', target],
          workingDirectory: path.join(packagesDir, 'isar_core_ffi'),
        );
        final binaryName = Platform.isWindows
            ? 'isar.dll'
            : Platform.isMacOS
                ? 'libisar.dylib'
                : 'libisar.so';
        await Isar.initializeIsarCore(
          libraries: {
            Abi.current(): path.join(
              path.dirname(packagesDir),
              'target',
              target,
              'debug',
              binaryName,
            ),
          },
        );
      } catch (e) {
        // ignore. maybe this is an instrumentation test
        print(e);
      }
    }

    _setUp = true;
  }
}

@isTest
void isarTest(
  String name,
  dynamic Function() body, {
  Timeout? timeout,
  bool skip = false,
  bool syncOnly = false,
}) {
  void runTest(bool syncTest) {
    final testName = syncTest ? '$name SYNC' : name;
    test(
      testName,
      () async {
        await runZoned(
          () async {
            try {
              await _prepareTest();
              await body();
              testCount++;
            } catch (e) {
              testErrors.add('$testName: $e');
              rethrow;
            }
          },
          zoneValues: {
            #syncTest: syncTest,
          },
        );
      },
      timeout: timeout ?? const Timeout(Duration(minutes: 5)),
    );
  }

  if (!syncOnly) {
    runTest(false);
  }

  if (!kIsWeb) {
    runTest(true);
  }
}

@isTest
void isarTestVm(String name, dynamic Function() body) {
  isarTest(name, body, skip: kIsWeb);
}

@isTest
void isarTestSync(String name, void Function() body) {
  isarTest(name, body, skip: kIsWeb, syncOnly: true);
}

String getRandomName() {
  final random = Random().nextInt(pow(2, 32) as int).toString();
  return '${random}_tmp';
}

String? testTempPath;
Future<Isar> openTempIsar(
  List<CollectionSchema<dynamic>> schemas, {
  String? name,
  String? directory,
  CompactCondition? compactOnLaunch,
}) async {
  await _prepareTest();
  if (!kIsWeb && testTempPath == null) {
    final dartToolDir = path.join(Directory.current.path, '.dart_tool');
    testTempPath = directory ?? path.join(dartToolDir, 'test', 'tmp');
    await Directory(testTempPath!).create(recursive: true);
  }

  final isar = await tOpen(
    schemas: schemas,
    name: name ?? getRandomName(),
    directory: kIsWeb ? '' : testTempPath!,
    compactOnLaunch: compactOnLaunch,
  );

  if (Invoker.current != null) {
    addTearDown(() async {
      if (isar.isOpen) {
        await isar.close(deleteFromDisk: true);
      }
    });
  }

  await isar.verify();
  return isar;
}

bool doubleListEquals(List<double?>? l1, List<double?>? l2) {
  if (l1?.length != l2?.length) {
    return false;
  }
  if (l1 != null && l2 != null) {
    for (var i = 0; i < l1.length; i++) {
      if (!doubleEquals(l1[i], l2[i])) {
        return false;
      }
    }
  }
  return true;
}

bool doubleEquals(double? d1, double? d2) {
  return d1 == d2 ||
      (d1 != null &&
          d2 != null &&
          ((d1.isNaN && d2.isNaN) || (d1 - d2).abs() < 0.001));
}

Matcher isIsarError([String? contains]) {
  return allOf(
    isA<IsarError>(),
    predicate(
      (IsarError e) =>
          contains == null ||
          e.toString().toLowerCase().contains(contains.toLowerCase()),
    ),
  );
}

Matcher throwsIsarError([String? contains]) {
  return throwsA(isIsarError(contains));
}

final Matcher throwsAssertionError = throwsA(isA<AssertionError>());

bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) {
    return b == null;
  }
  if (b == null || a.length != b.length) {
    return false;
  }
  if (identical(a, b)) {
    return true;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
