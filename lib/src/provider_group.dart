/// Canonical named-provider evidence. Unknown labels never count as diversity.
String? knownProviderGroup(String value) {
  final group = value.trim();
  return group.isEmpty || group.toLowerCase() == 'unknown' ? null : group;
}
