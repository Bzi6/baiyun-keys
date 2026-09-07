import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _baseUrl = 'https://www.pinganbaiyun.cn';
  static const String _newBaseUrl = 'https://xcx.pinganbaiyun.cn';
  static const String _defaultOpenId = 'o7fwU0bbq8M3IrfJMxIy2XwefFZM';

  static String? _cachedAccessToken;
  static DateTime? _tokenExpireTime;
  static String? _cachedRsaPublicKey;

  // ========== 旧接口（手机号+身份证） ==========

  static Future<Map<String, String>> loginOld(String phone, String idCard) async {
    final payload = {
      'sex': 0,
      'idcardNo': idCard,
      'deviceInfo': {
        'osVersion': '26.0',
        'wifiMac': '02:00:00:00:00:00',
        'brand': 'Apple',
        'os': 0,
        'udid': '2E382B94-EE0D-4918-9B9D-DDBE42E3E429',
        'appVersion': '1.3.6',
        'imsi': '46015',
        'model': 'iPhone15,3',
      },
      'faceUploadCount': 0,
      'isreal': 0,
      'age': 0,
      'appVersion': '1.3.6',
      'phone': phone,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/baiyunuser/account/login/v1'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    final data = jsonDecode(response.body);
    if (data['state'] != true || data['code'] != '0000') {
      throw Exception(data['msg'] ?? '登录失败');
    }

    final token = data['extension'] ?? '';
    final loginUser = data['obj'] != null && data['obj']['id'] != null ? data['obj']['id'].toString() : '';
    if (token.isEmpty || loginUser.isEmpty) {
      throw Exception('登录返回数据缺失');
    }

    return {'token': token, 'loginUser': loginUser, 'phone': phone};
  }

  static Future<List<Map<String, dynamic>>> fetchGuardListOld(Map<String, String> auth) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/baiyunuser/entranceguard/getList'),
      headers: {
        'Content-Type': 'application/json',
        'TOKEN': auth['token'] ?? '',
        'LOGIN_USER': auth['loginUser'] ?? '',
      },
      body: jsonEncode({'pageNum': 0, 'pages': 0, 'pageSize': 0}),
    );

    final data = jsonDecode(response.body);
    final List<dynamic> list = data['obj'] is List ? data['obj'] : [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ========== 新接口（只需手机号，全自动） ==========

  static Future<String> getAccessToken([String? openId]) async {
    final now = DateTime.now();
    if (_cachedAccessToken != null && _tokenExpireTime != null && now.isBefore(_tokenExpireTime!)) {
      return _cachedAccessToken!;
    }

    final id = openId ?? _defaultOpenId;
    final response = await http.post(
      Uri.parse('$_newBaseUrl/mini_program/api_01/check_state'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'openId': id, 'oper_type': 'INDEX'}),
    );

    final data = jsonDecode(response.body);
    if (data is List && data.isNotEmpty) {
      final token = data[0]['access_token'];
      if (token != null && token.toString().isNotEmpty) {
        _cachedAccessToken = token.toString();
        _tokenExpireTime = now.add(const Duration(minutes: 30));
        return _cachedAccessToken!;
      }
      throw Exception(data[0]['resp_msg'] ?? '获取 access_token 失败');
    }
    throw Exception('check_state 返回数据格式异常');
  }

  static Future<String> getRsaPublicKey(String accessToken) async {
    if (_cachedRsaPublicKey != null && _cachedRsaPublicKey!.isNotEmpty) {
      return _cachedRsaPublicKey!;
    }

    final response = await http.get(
      Uri.parse('$_newBaseUrl/health_passport/api_001_health_passport/get_rsa_public_key'),
      headers: {
        'Content-Type': 'application/json',
        'cloud_shield_token': accessToken,
      },
    );

    final data = jsonDecode(response.body);
    if (data is List && data.isNotEmpty) {
      final key = data[0]['result'];
      if (key != null && key.toString().isNotEmpty) {
        _cachedRsaPublicKey = key.toString();
        return _cachedRsaPublicKey!;
      }
      throw Exception(data[0]['resp_msg'] ?? '获取 RSA 公钥失败');
    }
    throw Exception('get_rsa_public_key 返回数据格式异常');
  }

  static Future<List<Map<String, dynamic>>> getGuardListByPhone(String phone, String accessToken, String rsaPublicKey) async {
    final plaintext = jsonEncode({'phone': phone});
    final encryptedKey = rsaEncrypt(plaintext, rsaPublicKey);

    final response = await http.post(
      Uri.parse('$_newBaseUrl/p_021_health_passport/api_007_wbyw_002/get_guard_list_by_phone'),
      headers: {
        'Content-Type': 'application/json',
        'cloud_shield_token': accessToken,
      },
      body: jsonEncode({'key': encryptedKey}),
    );

    final data = jsonDecode(response.body);
    if (data is List && data.isNotEmpty) {
      final first = data[0];
      if (first['resp_code'] != null && first['resp_code'] != '000000000000') {
        throw Exception(first['resp_msg'] ?? '获取门禁列表失败');
      }
      if (first['data_list'] is List) {
        return (first['data_list'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    }
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e)).toList();
    throw Exception('get_guard_list_by_phone 返回数据格式异常');
  }

  static Future<Map<String, dynamic>> fetchConfigByPhone(String phone) async {
    final accessToken = await getAccessToken();
    final rsaPublicKey = await getRsaPublicKey(accessToken);
    final guardList = await getGuardListByPhone(phone, accessToken, rsaPublicKey);
    return {
      'accessToken': accessToken,
      'rsaPublicKey': rsaPublicKey,
      'guardList': guardList,
    };
  }

  static String deriveMacFromBluetoothName(String bluetoothName, [String macPrefix = '3E5']) {
    final clean = bluetoothName.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (clean.length < 11) return '';
    final suffix = clean.substring(clean.length - 9);
    final full = macPrefix.toUpperCase() + suffix;
    if (full.length != 12) return '';
    return '${full.substring(0, 2)}:${full.substring(2, 4)}:${full.substring(4, 6)}:${full.substring(6, 8)}:${full.substring(8, 10)}:${full.substring(10, 12)}';
  }

  // ========== RSA 加密（PKCS#1 v1.5，与小程序一致） ==========

  static String rsaEncrypt(String plaintext, String publicKeyPem, {int blockSize = 30}) {
    final key = _parsePublicKey(publicKeyPem);
    final messageBytes = _utf8Encode(plaintext);

    var encryptedHex = '';
    for (var i = 0; i < messageBytes.length; i += blockSize) {
      final end = (i + blockSize < messageBytes.length) ? i + blockSize : messageBytes.length;
      final block = messageBytes.sublist(i, end);
      final encrypted = _rsaEncryptBlock(block, key);
      encryptedHex += _bytesToHex(encrypted);
    }

    return '${encryptedHex}RSA_STRTOK@@@';
  }

  static Map<String, dynamic> _parsePublicKey(String pem) {
    final b64 = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll(RegExp(r'\s'), '');

    final der = _base64Decode(b64);
    var offset = 0;

    // 外层 SEQUENCE
    if (der[offset] != 0x30) throw Exception('Invalid public key: expected SEQUENCE');
    offset++;
    final len1 = _readLength(der, offset);
    offset = len1['offset'] as int;

    // AlgorithmIdentifier SEQUENCE
    if (der[offset] != 0x30) throw Exception('Invalid public key: expected AlgorithmIdentifier');
    offset++;
    final algLen = _readLength(der, offset);
    offset = (algLen['offset'] as int) + (algLen['length'] as int);

    // subjectPublicKey BIT STRING
    if (der[offset] != 0x03) throw Exception('Invalid public key: expected BIT STRING');
    offset++;
    final bitStrLen = _readLength(der, offset);
    offset = bitStrLen['offset'] as int;
    offset++; // unusedBits

    // RSAPublicKey SEQUENCE
    if (der[offset] != 0x30) throw Exception('Invalid public key: expected RSAPublicKey SEQUENCE');
    offset++;
    final rsaLen = _readLength(der, offset);
    offset = rsaLen['offset'] as int;

    // modulus (n)
    if (der[offset] != 0x02) throw Exception('Invalid public key: expected modulus INTEGER');
    offset++;
    final nLen = _readLength(der, offset);
    offset = nLen['offset'] as int;
    final nBytes = der.sublist(offset, offset + (nLen['length'] as int));
    offset += nLen['length'] as int;
    final n = _bytesToBigInt(nBytes);

    // publicExponent (e)
    if (der[offset] != 0x02) throw Exception('Invalid public key: expected exponent INTEGER');
    offset++;
    final eLen = _readLength(der, offset);
    offset = eLen['offset'] as int;
    final eBytes = der.sublist(offset, offset + (eLen['length'] as int));
    final e = _bytesToBigInt(eBytes);

    return {'n': n, 'e': e, 'keyLength': (n.toRadixString(16).length / 2).ceil()};
  }

  static Map<String, int> _readLength(Uint8List bytes, int offset) {
    final first = bytes[offset];
    offset++;
    if (first < 0x80) {
      return {'length': first, 'offset': offset};
    }
    final numBytes = first & 0x7f;
    var length = 0;
    for (var i = 0; i < numBytes; i++) {
      length = (length << 8) | bytes[offset + i];
    }
    return {'length': length, 'offset': offset + numBytes};
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final bytes = Uint8List(length);
    for (var i = length - 1; i >= 0; i--) {
      bytes[i] = (value & BigInt.from(0xff)).toInt();
      value >>= 8;
    }
    return bytes;
  }

  static Uint8List _rsaEncryptBlock(Uint8List message, Map<String, dynamic> publicKey) {
    final n = publicKey['n'] as BigInt;
    final e = publicKey['e'] as BigInt;
    final keyLength = publicKey['keyLength'] as int;

    final padded = _pkcs1Pad(message, keyLength);
    final m = _bytesToBigInt(padded);
    final c = m.modPow(e, n);
    return _bigIntToBytes(c, keyLength);
  }

  static Uint8List _pkcs1Pad(Uint8List message, int keyLength) {
    final msgLen = message.length;
    final padLen = keyLength - msgLen - 3;
    if (padLen < 8) {
      throw Exception('Message too long for RSA key size');
    }

    final padded = Uint8List(keyLength);
    padded[0] = 0x00;
    padded[1] = 0x02;

    final random = Random.secure();
    for (var i = 0; i < padLen; i++) {
      var b = random.nextInt(256);
      while (b == 0) {
        b = random.nextInt(256);
      }
      padded[2 + i] = b;
    }

    padded[2 + padLen] = 0x00;
    padded.setRange(3 + padLen, 3 + padLen + msgLen, message);
    return padded;
  }

  static Uint8List _utf8Encode(String str) {
    final bytes = <int>[];
    for (var i = 0; i < str.length; i++) {
      var code = str.codeUnitAt(i);
      if (code < 0x80) {
        bytes.add(code);
      } else if (code < 0x800) {
        bytes.add(0xc0 | (code >> 6));
        bytes.add(0x80 | (code & 0x3f));
      } else if (code >= 0xd800 && code <= 0xdbff) {
        final next = str.codeUnitAt(++i);
        code = 0x10000 + ((code & 0x3ff) << 10) + (next & 0x3ff);
        bytes.add(0xf0 | (code >> 18));
        bytes.add(0x80 | ((code >> 12) & 0x3f));
        bytes.add(0x80 | ((code >> 6) & 0x3f));
        bytes.add(0x80 | (code & 0x3f));
      } else {
        bytes.add(0xe0 | (code >> 12));
        bytes.add(0x80 | ((code >> 6) & 0x3f));
        bytes.add(0x80 | (code & 0x3f));
      }
    }
    return Uint8List.fromList(bytes);
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _base64Decode(String b64) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final lookup = Uint8List(256);
    for (var i = 0; i < chars.length; i++) {
      lookup[chars.codeUnitAt(i)] = i;
    }
    final clean = b64.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
    final bytes = <int>[];
    var buffer = 0;
    var bits = 0;
    for (var i = 0; i < clean.length; i++) {
      final c = clean.codeUnitAt(i);
      if (c == 61) break;
      buffer = (buffer << 6) | lookup[c];
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        bytes.add((buffer >> bits) & 0xff);
      }
    }
    return Uint8List.fromList(bytes);
  }
}
