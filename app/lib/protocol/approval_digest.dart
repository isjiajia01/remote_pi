import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Matches extension argumentDigest: recursively sort keys by UTF-16 units,
/// preserve array order, and use JSON.stringify's number representation.
String canonicalApprovalArgs(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort(_compareUtf16);
    return '{${keys.map((key) => '${jsonEncode(key)}:${canonicalApprovalArgs(value[key])}').join(',')}}';
  }
  if (value is List) {
    return '[${value.map(canonicalApprovalArgs).join(',')}]';
  }
  if (value is num) return _jsonNumber(value);
  if (value == null || value is String || value is bool) {
    return jsonEncode(value);
  }
  throw const FormatException('Tool arguments must be JSON');
}

int _compareUtf16(String a, String b) {
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final difference = a.codeUnitAt(i) - b.codeUnitAt(i);
    if (difference != 0) return difference;
  }
  return a.length - b.length;
}

String _jsonNumber(num value) {
  final number = value.toDouble();
  if (!number.isFinite) throw const FormatException('Non-finite argument');
  if (number == 0) return '0';
  final text = number.abs().toString().toLowerCase();
  final parts = text.split('e');
  final mantissa = parts.first;
  final exponent = parts.length == 2 ? int.parse(parts.last) : 0;
  final dot = mantissa.indexOf('.');
  var digits = mantissa.replaceAll('.', '');
  final position = (dot < 0 ? mantissa.length : dot) + exponent;
  while (digits.endsWith('0') && digits.length > 1) {
    digits = digits.substring(0, digits.length - 1);
  }
  String result;
  if (number.abs() >= 1e21 || number.abs() < 1e-6) {
    final exp = position - 1;
    result =
        '${digits[0]}${digits.length > 1 ? '.${digits.substring(1)}' : ''}e${exp >= 0 ? '+' : ''}$exp';
  } else if (position <= 0) {
    result = '0.${'0' * -position}$digits';
  } else if (position >= digits.length) {
    result = '$digits${'0' * (position - digits.length)}';
  } else {
    result = '${digits.substring(0, position)}.${digits.substring(position)}';
  }
  return number < 0 ? '-$result' : result;
}

Future<String> approvalArgsDigest(Object? args) async {
  final hash = await Sha256().hash(utf8.encode(canonicalApprovalArgs(args)));
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
