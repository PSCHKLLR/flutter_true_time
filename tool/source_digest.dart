import 'dart:convert';
import 'dart:io';
import 'release_support.dart';

/// Read-only fingerprint for CI artifacts and independently resolved lanes.
void main() {
  final root = Directory.current;
  final inputs = readInputs(root, {
    ...gitInputs(root),
    ...gitInputs(root, untracked: true),
  });
  stdout.writeln(
    jsonEncode({'sourceDigest': sourceDigest(inputs), 'inputs': inputs}),
  );
}
