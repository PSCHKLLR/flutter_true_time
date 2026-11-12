import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'host lane round trips remove legacy DSL and align built-in compiler in settings',
    () async {
      final root = Directory.systemTemp.createTempSync('true_time_android_');
      addTearDown(() {
        final resolved = root.resolveSymbolicLinksSync();
        if (Directory(resolved).parent.path !=
                Directory.systemTemp.resolveSymbolicLinksSync() ||
            !resolved
                .split(Platform.pathSeparator)
                .last
                .startsWith('true_time_android_')) {
          throw StateError('Unexpected cleanup target');
        }
        root.deleteSync(recursive: true);
      });
      for (final name in [
        'settings.gradle.kts',
        'app/build.gradle.kts',
        'build.gradle.kts',
        'gradle.properties',
        'gradle/wrapper/gradle-wrapper.properties',
      ]) {
        final file = File('${root.path}/example/android/$name');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          File('example/android/$name').readAsStringSync(),
        );
      }
      final script = File('tool/configure_android.dart').absolute.path;
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      final executable = flutterRoot == null
          ? Platform.resolvedExecutable
          : '$flutterRoot/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
      String read(String name) =>
          File('${root.path}/example/android/$name').readAsStringSync();
      for (final lane in ['builtin', 'builtin', 'current', 'baseline']) {
        final child = await Process.start(executable, [
          script,
          lane,
        ], workingDirectory: root.path);
        final error = child.stderr.transform(utf8.decoder).join();
        final output = child.stdout.drain<void>();
        var finished = false;
        try {
          final code = await child.exitCode.timeout(
            const Duration(seconds: 15),
          );
          finished = true;
          expect(code, 0, reason: await error);
          await output;
        } finally {
          if (!finished) {
            child.kill();
            await child.exitCode;
          }
        }
        final app = read('app/build.gradle.kts'),
            settings = read('settings.gradle.kts');
        expect(app, contains('ApplicationExtension'));
        expect(app, isNot(contains('kotlinOptions')));
        expect(
          read('build.gradle.kts'),
          isNot(contains('built-in compiler alignment')),
        );
        if (lane == 'builtin') {
          expect(app, isNot(contains('id("kotlin-android")')));
          expect(
            settings,
            isNot(contains('id("org.jetbrains.kotlin.android")')),
          );
          expect(
            RegExp(
              'BEGIN true_time built-in compiler alignment',
            ).allMatches(settings).length,
            1,
          );
          expect(
            settings.indexOf('buildscript {'),
            lessThan(settings.indexOf('plugins {')),
          );
          expect(settings, contains('kotlin-gradle-plugin:2.4.0'));
          expect(
            read('gradle.properties'),
            contains('android.builtInKotlin=true'),
          );
        } else {
          expect(app, contains('compilerOptions'));
          expect(settings, isNot(contains('built-in compiler alignment')));
          expect(settings, contains(lane == 'baseline' ? '2.2.20' : '2.4.0'));
          expect(
            read('gradle.properties'),
            contains('android.builtInKotlin=false'),
          );
        }
      }
    },
  );
}
