import 'dart:typed_data';
import 'des_service.dart';

/// 蓝牙协议服务
/// 对应小程序中的 bleProtocol.js + lockBiz.js
class LockProtocol {
  // ========== 工具函数 ==========
  static Uint8List hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    final padded = clean.length % 2 == 0 ? clean : '0$clean';
    final bytes = Uint8List(padded.length ~/ 2);
    for (var i = 0; i < padded.length; i += 2) {
      bytes[i ~/ 2] = int.parse(padded.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }

  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  static int _sumBytes(Uint8List bytes) {
    var sum = 0;
    for (final b in bytes) {
      sum += b;
    }
    return sum;
  }

  static int _xorBytes(Uint8List bytes) {
    if (bytes.isEmpty) return 0;
    var acc = bytes[0];
    for (var i = 1; i < bytes.length; i++) {
      acc ^= bytes[i];
    }
    return acc & 0xff;
  }

  static int _complementByte(int sum) {
    return (~(sum & 0xff) + 256) & 0xff;
  }

  // ========== MAC 和蓝牙名称处理 ==========
  static bool isValidMac(String mac) {
    return RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(mac.trim());
  }

  static Uint8List macToBytes(String mac) {
    if (!isValidMac(mac)) throw Exception('MAC 格式错误');
    final segments = mac.split(':');
    return Uint8List.fromList(segments.map((s) => int.parse(s, radix: 16)).toList());
  }

  static String deriveBluetoothNameFromMac(String mac) {
    final clean = mac.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    return clean.length == 12 ? 'BY${clean.substring(clean.length - 9)}' : '';
  }

  static String normalizeBluetoothName(String name) {
    return (name).toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
  }

  static List<int> extractDeviceIdParts(String name) {
    final clean = name.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (clean.length < 11) {
      throw Exception('蓝牙名称格式不合法，无法解析设备标识');
    }
    return [
      int.parse(clean.substring(3, 5), radix: 16),
      int.parse(clean.substring(5, 7), radix: 16),
      int.parse(clean.substring(7, 9), radix: 16),
      int.parse(clean.substring(9, 11), radix: 16),
    ];
  }

  // ========== 密钥验证 ==========
  static bool isValidKey(String key) {
    final sanitized = key.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    return sanitized.length >= 16 &&
        sanitized.length <= 32 &&
        sanitized.length % 2 == 0 &&
        RegExp(r'^[0-9A-F]+$').hasMatch(sanitized);
  }

  static String sanitizeKey(String key) {
    return key.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
  }

  // ========== 握手指令 ==========
  static Uint8List buildHandshakeCommand(Uint8List random, String bluetoothName, String productKey) {
    final ids = extractDeviceIdParts(bluetoothName);
    return buildHandshakeCommandWithHeader(random, ids, productKey);
  }

  static Uint8List buildHandshakeCommandWithHeader(Uint8List random, List<int> headerBytes, String productKey) {
    if (headerBytes.length != 4) {
      throw Exception('握手指令头部需提供 4 个字节');
    }
    var sum = _sumBytes(random);
    final keyBytes = hexToBytes(sanitizeKey(productKey));
    sum += _sumBytes(keyBytes);
    final low = sum & 0xff;
    final high = (sum >> 8) & 0xff;
    final temp = Uint8List.fromList([low, high, random[0], random[1], random[2], random[3], 0, 0]);
    final encryptedHex = DesService.encryptBlockHex(productKey, bytesToHex(temp));
    final encryptedBytes = hexToBytes(encryptedHex);
    final frame = <int>[
      0xa5,
      0x14,
      0x05,
      ...headerBytes,
      0x00,
      0x01,
      0x07,
      ...encryptedBytes,
      0x00,
      0x5a,
    ];
    final checksum = _sumBytes(Uint8List.fromList(frame));
    frame[frame.length - 2] = _complementByte(checksum);
    return Uint8List.fromList(frame);
  }

  /// 用 MAC 后 4 字节构建握手指令（与小程序版一致）
  static Uint8List buildHandshakeCommandWithMac(Uint8List random, String mac, String productKey) {
    final macBytes = macToBytes(mac);
    final headerBytes = macBytes.sublist(2, 6);
    return buildHandshakeCommandWithHeader(random, headerBytes, productKey);
  }

  // ========== 通信密钥指令 ==========
  static Uint8List buildCommKeyCommand(Uint8List random, String derivedName, String productKey) {
    final ids = extractDeviceIdParts(derivedName);
    // 修复：pivot 必须为 8 字节（DES 要求），补两个 0
    final pivot = Uint8List.fromList([random[0], random[1], random[2], random[3], 0, 0, 0, 0]);
    final encryptedHex = DesService.encryptBlockHex(productKey, bytesToHex(pivot));
    final encryptedBytes = hexToBytes(encryptedHex);
    final deviceHex = bytesToHex(Uint8List.fromList(ids));
    final bodyHex = '$deviceHex' '0000' '${bytesToHex(random)}';
    final bodyBytes = hexToBytes(bodyHex);
    final sumBody = _sumBytes(bodyBytes) & 0xff;
    final xorBody = _xorBytes(bodyBytes);
    final frame = <int>[
      0xa5,
      0x16,
      0x01,
      ...ids,
      0x00,
      0x00,
      sumBody,
      xorBody,
      0x09,
      ...encryptedBytes,
      0x00,
      0x5a,
    ];
    final checksum = _sumBytes(Uint8List.fromList(frame));
    frame[frame.length - 2] = _complementByte(checksum);
    return Uint8List.fromList(frame);
  }

  // ========== 时间同步指令 ==========
  static Uint8List buildTimeSyncCommand(Uint8List timeBytes, String derivedName, String sessionKey) {
    final payload = Uint8List.fromList([...timeBytes, 0]);
    final ids = extractDeviceIdParts(derivedName);
    final encryptedHex = DesService.encryptBlockHex(sessionKey, bytesToHex(payload));
    final encryptedBytes = hexToBytes(encryptedHex);
    final bodyHex = '${bytesToHex(Uint8List.fromList(ids))}' '0000' '${bytesToHex(timeBytes)}';
    final bodyBytes = hexToBytes(bodyHex);
    final sumBody = _sumBytes(bodyBytes) & 0xff;
    final xorBody = _xorBytes(bodyBytes);
    final frame = <int>[
      0xa5,
      0x16,
      0x01,
      ...ids,
      0x00,
      0x00,
      sumBody,
      xorBody,
      0x06,
      ...encryptedBytes,
      0x00,
      0x5a,
    ];
    final checksum = _sumBytes(Uint8List.fromList(frame));
    frame[frame.length - 2] = _complementByte(checksum);
    return Uint8List.fromList(frame);
  }

  static String generateTimeHex([DateTime? date]) {
    final now = date ?? DateTime.now();
    final year = now.year - 2000;
    final yearHigh = (year ~/ 10) & 0x0f;
    final yearLow = (year % 10) & 0x0f;
    final yearHex = ((yearHigh << 4) | yearLow).toRadixString(16).padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    const weekdayMap = ['00', '01', '02', '03', '04', '05', '06'];
    final weekday = weekdayMap[now.weekday % 7];
    return '$yearHex$month$day$hour$minute$second$weekday'.toUpperCase();
  }

  // ========== 解密通信密钥 ==========
  static String decryptCommKey(String bodyHex, String productKey) {
    final decrypted = DesService.decryptBlockHex(productKey, bodyHex);
    if (decrypted.length < 32) return '';
    return decrypted.substring(16, 32).toUpperCase();
  }

  // ========== 加密开锁指令（来自 lockBiz.js） ==========
  static Uint8List encryptUnlockCommand(Uint8List seed, String mac, String key) {
    final macBytes = macToBytes(mac);
    final sanitizedKey = sanitizeKey(key);
    final keyBytes = hexToBytes(sanitizedKey);
    var sum = 0;
    for (final b in seed) {
      sum += b;
    }
    for (final b in keyBytes) {
      sum += b;
    }
    final sumBytes = Uint8List.fromList([sum & 0xff, (sum >> 8) & 0xff]);
    final paddedLength = ((sumBytes.length + seed.length) / 8).ceil() * 8;
    final padded = Uint8List(paddedLength);
    padded.setAll(0, sumBytes);
    padded.setAll(sumBytes.length, seed);
    final encryptedHex = DesService.encryptBlockHex(sanitizedKey, bytesToHex(padded));
    final encryptedBytes = hexToBytes(encryptedHex);
    final headerSubset = macBytes.sublist(2, 6);
    final totalLength = encryptedBytes.length + 12;
    final payload = Uint8List(totalLength);
    payload[0] = 0xa5;
    payload[1] = totalLength & 0xff;
    payload[2] = 0x05;
    payload.setAll(3, headerSubset);
    payload[7] = 0x00;
    payload[8] = 0x01;
    payload[9] = 0x07;
    payload.setAll(10, encryptedBytes);
    payload[totalLength - 2] = 0x00;
    payload[totalLength - 1] = 0x5a;
    var checksum = 0;
    for (final b in payload) {
      checksum += b;
    }
    payload[totalLength - 2] = (~checksum) & 0xff;
    return payload;
  }

  // ========== 解析开锁结果 ==========
  static Map<String, String> decodeOpenResult(String frameHex, String productKey) {
    final clean = frameHex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (clean.length < 36) {
      return {'code': 'FF', 'message': '数据长度不足，无法解析回执'};
    }
    final msgBodyHex = clean.substring(20, 36);
    final decrypted = DesService.decryptBlockHex(productKey, msgBodyHex);
    if (decrypted.length != 16) {
      return {'code': 'FF', 'message': '回执解密失败'};
    }
    final status = decrypted.substring(4, 6);
    if (status == '00') {
      return {'code': status, 'message': '开门成功'};
    }
    if (status == '02') {
      return {'code': status, 'message': '门已打开'};
    }
    return {'code': status, 'message': '开门失败，密码无效'};
  }
}
