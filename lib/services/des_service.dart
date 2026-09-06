import 'dart:typed_data';

/// DES 加密服务（ECB 模式，无填充）
/// 对应小程序中的 des.js
class DesService {
  /// DES 加密（8字节块）
  static String encryptBlockHex(String keyHex, String dataHex) {
    final key = _normalizeKey(keyHex);
    final data = _normalizeData(dataHex);
    final encrypted = _desEncrypt(key, data);
    return _bytesToHex(encrypted).toUpperCase();
  }

  /// DES 解密（8字节块）
  static String decryptBlockHex(String keyHex, String dataHex) {
    final key = _normalizeKey(keyHex);
    final data = _normalizeData(dataHex);
    final decrypted = _desDecrypt(key, data);
    return _bytesToHex(decrypted).toUpperCase();
  }

  static Uint8List _normalizeKey(String keyHex) {
    final clean = keyHex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (clean.length < 16) throw Exception('密钥长度不足 8 字节');
    return _hexToBytes(clean.substring(0, 16));
  }

  static Uint8List _normalizeData(String dataHex) {
    final clean = dataHex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (clean.length != 16) throw Exception('DES 数据块必须为 8 字节');
    return _hexToBytes(clean);
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      bytes[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // DES S-boxes
  static const List<List<int>> _sBoxes = [
    [
      14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7,
      0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
      4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0,
      15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13
    ],
    [
      15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10,
      3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5,
      0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15,
      13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9
    ],
    [
      10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8,
      13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
      13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7,
      1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12
    ],
    [
      7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15,
      13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
      10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4,
      3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14
    ],
    [
      2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9,
      14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
      4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14,
      11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3
    ],
    [
      12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11,
      10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
      9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6,
      4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13
    ],
    [
      4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1,
      13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
      1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2,
      6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12
    ],
    [
      13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7,
      1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
      7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8,
      2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11
    ],
  ];

  static const List<int> _ipTable = [
    58, 50, 42, 34, 26, 18, 10, 2,
    60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6,
    64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9, 1,
    59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5,
    63, 55, 47, 39, 31, 23, 15, 7
  ];

  static const List<int> _fpTable = [
    40, 8, 48, 16, 56, 24, 64, 32,
    39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30,
    37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28,
    35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26,
    33, 1, 41, 9, 49, 17, 57, 25
  ];

  static const List<int> _eTable = [
    32, 1, 2, 3, 4, 5,
    4, 5, 6, 7, 8, 9,
    8, 9, 10, 11, 12, 13,
    12, 13, 14, 15, 16, 17,
    16, 17, 18, 19, 20, 21,
    20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29,
    28, 29, 30, 31, 32, 1
  ];

  static const List<int> _pTable = [
    16, 7, 20, 21, 29, 12, 28, 17,
    1, 15, 23, 26, 5, 18, 31, 10,
    2, 8, 24, 14, 32, 27, 3, 9,
    19, 13, 30, 6, 22, 11, 4, 25
  ];

  static const List<int> _pc1Table = [
    57, 49, 41, 33, 25, 17, 9,
    1, 58, 50, 42, 34, 26, 18,
    10, 2, 59, 51, 43, 35, 27,
    19, 11, 3, 60, 52, 44, 36,
    63, 55, 47, 39, 31, 23, 15,
    7, 62, 54, 46, 38, 30, 22,
    14, 6, 61, 53, 45, 37, 29,
    21, 13, 5, 28, 20, 12, 4
  ];

  static const List<int> _pc2Table = [
    14, 17, 11, 24, 1, 5,
    3, 28, 15, 6, 21, 10,
    23, 19, 12, 4, 26, 8,
    16, 7, 27, 20, 13, 2,
    41, 52, 31, 37, 47, 55,
    30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53,
    46, 42, 50, 36, 29, 32
  ];

  static const List<int> _shifts = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];

  static List<int> _permute(List<int> input, List<int> table) {
    return table.map((i) => input[i - 1]).toList();
  }

  static List<int> _leftShift(List<int> input, int shift) {
    final result = List<int>.from(input);
    for (var i = 0; i < shift; i++) {
      result.add(result.removeAt(0));
    }
    return result;
  }

  static List<List<int>> _generateSubkeys(Uint8List key) {
    final keyBits = _bytesToBits(key);
    final permutedKey = _permute(keyBits, _pc1Table);
    var c = permutedKey.sublist(0, 28);
    var d = permutedKey.sublist(28, 56);
    final subkeys = <List<int>>[];
    for (var i = 0; i < 16; i++) {
      c = _leftShift(c, _shifts[i]);
      d = _leftShift(d, _shifts[i]);
      final combined = [...c, ...d];
      subkeys.add(_permute(combined, _pc2Table));
    }
    return subkeys;
  }

  static List<int> _bytesToBits(Uint8List bytes) {
    final bits = <int>[];
    for (final byte in bytes) {
      for (var i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1);
      }
    }
    return bits;
  }

  static Uint8List _bitsToBytes(List<int> bits) {
    final bytes = Uint8List(bits.length ~/ 8);
    for (var i = 0; i < bytes.length; i++) {
      var byte = 0;
      for (var j = 0; j < 8; j++) {
        byte = (byte << 1) | bits[i * 8 + j];
      }
      bytes[i] = byte;
    }
    return bytes;
  }

  static List<int> _feistel(List<int> right, List<int> subkey) {
    final expanded = _permute(right, _eTable);
    final xored = List<int>.generate(expanded.length, (i) => expanded[i] ^ subkey[i]);
    final output = <int>[];
    for (var i = 0; i < 8; i++) {
      final block = xored.sublist(i * 6, (i + 1) * 6);
      final row = (block[0] << 1) | block[5];
      final col = (block[1] << 3) | (block[2] << 2) | (block[3] << 1) | block[4];
      final value = _sBoxes[i][row * 16 + col];
      for (var j = 3; j >= 0; j--) {
        output.add((value >> j) & 1);
      }
    }
    return _permute(output, _pTable);
  }

  static Uint8List _desEncrypt(Uint8List key, Uint8List data) {
    final subkeys = _generateSubkeys(key);
    final dataBits = _bytesToBits(data);
    final permuted = _permute(dataBits, _ipTable);
    var left = permuted.sublist(0, 32);
    var right = permuted.sublist(32, 64);
    for (var i = 0; i < 16; i++) {
      final newRight = List<int>.generate(32, (j) => left[j] ^ _feistel(right, subkeys[i])[j]);
      left = right;
      right = newRight;
    }
    final combined = [...right, ...left];
    final finalPermuted = _permute(combined, _fpTable);
    return _bitsToBytes(finalPermuted);
  }

  static Uint8List _desDecrypt(Uint8List key, Uint8List data) {
    final subkeys = _generateSubkeys(key);
    final dataBits = _bytesToBits(data);
    final permuted = _permute(dataBits, _ipTable);
    var left = permuted.sublist(0, 32);
    var right = permuted.sublist(32, 64);
    for (var i = 15; i >= 0; i--) {
      final newRight = List<int>.generate(32, (j) => left[j] ^ _feistel(right, subkeys[i])[j]);
      left = right;
      right = newRight;
    }
    final combined = [...right, ...left];
    final finalPermuted = _permute(combined, _fpTable);
    return _bitsToBytes(finalPermuted);
  }
}
