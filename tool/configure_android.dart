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
  var value = settings.readAsStringSync().replaceAll(
    RegExp(
      r'// BEGIN true_time built-in compiler alignment[\s\S]*?// END true_time built-in compiler alignment\s*',
    ),
    '',
  );
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
  if (lane == 'builtin') {
    // Settings owns AGP's plugin classloader; align KGP here before loading AGP.
    value = value.replaceFirst(
      RegExp(r'^plugins\s*\{', multiLine: true),
      '// BEGIN true_time built-in compiler alignment\nbuildscript { repositories { google(); mavenCentral() }; dependencies { classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin") } }\n// END true_time built-in compiler alignment\nplugins {',
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
  value = value.replaceFirst(
    RegExp(r'^android\s*\{', multiLine: true),
    'extensions.configure<com.android.build.api.dsl.ApplicationExtension> {',
  );
  value = value.replaceAll(RegExp(r'\s*kotlinOptions\s*\{[^}]*\}\s*'), '\n');
  value = value.replaceAll(
    RegExp(
      r'// BEGIN true_time Kotlin compiler target[\s\S]*?// END true_time Kotlin compiler target\s*',
    ),
    '',
  );
  if (lane != 'builtin') {
    value +=
        '\n// BEGIN true_time Kotlin compiler target\nkotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }\n// END true_time Kotlin compiler target\n';
  }
  final hostBuild = File('example/android/build.gradle.kts');
  final hostValue = hostBuild.readAsStringSync().replaceAll(
    RegExp(
      r'// BEGIN true_time built-in compiler alignment[\s\S]*?// END true_time built-in compiler alignment\s*',
    ),
    '',
  );
  hostBuild.writeAsStringSync(hostValue);
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
