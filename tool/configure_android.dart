import 'dart:io';

/// Configures only the checked-in example host. Run from the package root.
void main(List<String> args) {
  final lane = args.singleOrNull ?? 'baseline';
  if (!['baseline', 'current', 'builtin'].contains(lane)) {
    throw ArgumentError('Use baseline, current, or builtin');
  }
  final agp = lane == 'baseline' ? '8.11.1' : '9.1.0';
  final kotlin = lane == 'baseline' ? '2.2.20' : '2.4.0';
  final gradle = lane == 'baseline' ? '8.14' : '9.3.1';
  final settings = File('example/android/settings.gradle.kts');
  var value = settings.readAsStringSync();
  final agpPattern = RegExp(r'id\("com.android.application"\) version "[^"]+"');
  if (!agpPattern.hasMatch(value)) {
    throw StateError('Unexpected Android host template');
  }
  value = value.replaceFirst(
    agpPattern,
    'id("com.android.application") version "$agp"',
  );
  final kgpPattern = RegExp(
    r'^.*id\("org.jetbrains.kotlin.android"\).*$',
    multiLine: true,
  );
  value = value.replaceAll(kgpPattern, '');
  if (lane != 'builtin') {
    value = value.replaceFirst(
      'id("dev.flutter.flutter-plugin-loader") version "1.0.0"',
      'id("dev.flutter.flutter-plugin-loader") version "1.0.0"\n    id("org.jetbrains.kotlin.android") version "$kotlin" apply false',
    );
  }
  settings.writeAsStringSync(value);
  final app = File('example/android/app/build.gradle.kts');
  value = app.readAsStringSync().replaceAll(
    RegExp(
      r'^.*id\("(kotlin-android|org.jetbrains.kotlin.android)"\).*$',
      multiLine: true,
    ),
    '',
  );
  if (lane != 'builtin') {
    value = value.replaceFirst(
      'id("com.android.application")',
      'id("com.android.application")\n    id("kotlin-android")',
    );
  }
  // Built-in Kotlin inherits Java targetCompatibility; the legacy
  // android.kotlinOptions DSL requires the Kotlin Android plugin.
  value = value.replaceAll(RegExp(r'\s*kotlinOptions\s*\{[^}]*\}\s*'), '\n');
  if (lane != 'builtin') {
    value = value.replaceFirst(
      'defaultConfig {',
      'kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }\n\n    defaultConfig {',
    );
  }
  app.writeAsStringSync(value);
  final wrapper = File(
    'example/android/gradle/wrapper/gradle-wrapper.properties',
  );
  wrapper.writeAsStringSync(
    wrapper.readAsStringSync().replaceAll(
      RegExp(r'gradle-[0-9.]+-(all|bin)\.zip'),
      'gradle-$gradle-all.zip',
    ),
  );
  final properties = File('example/android/gradle.properties');
  value = properties.readAsStringSync().replaceAll(
    RegExp(
      r'^(android\.(builtInKotlin|newDsl)|flutterTrueTimeAgpVersion)=.*\r?\n?',
      multiLine: true,
    ),
    '',
  );
  properties.writeAsStringSync(
    '$value\nflutterTrueTimeAgpVersion=$agp\nandroid.builtInKotlin=${lane == 'builtin' ? 'true' : 'false'}\nandroid.newDsl=false\n',
  );
  stdout.writeln('Configured Android lane: $lane (AGP $agp, Gradle $gradle)');
}
