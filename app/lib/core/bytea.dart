import 'dart:typed_data';

/// Format bytea de PostgREST : « \x » suivi de l'hexadécimal.
String toBytea(List<int> b) {
  final s = StringBuffer(r'\x');
  for (final x in b) {
    s.write(x.toRadixString(16).padLeft(2, '0'));
  }
  return s.toString();
}

Uint8List fromBytea(dynamic v) {
  final str = v as String;
  final s = str.startsWith(r'\x') ? str.substring(2) : str;
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}
