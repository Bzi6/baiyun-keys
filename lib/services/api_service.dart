import 'dart:convert';
import 'package:http/http.dart' as http;

/// 平安白云 API 服务（对应小程序 utils/api.js）
class ApiService {
  static const String baseUrl = 'https://www.pinganbaiyun.cn';

  /// 模拟微信小程序 User-Agent（必须带，否则接口返回维护提示）
  static const String miniProgramUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
      'MicroMessenger/8.0.40(0x18002824) NetType/WIFI Language/zh_CN miniProgram';

  /// 登录
  static Future<Map<String, dynamic>> login(String phone, String idcardNo) async {
    final body = {
      'phone': phone,
      'idcardNo': idcardNo,
      'sex': 0,
      'deviceInfo': {
        'osVersion': '17.0',
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
    };

    final response = await http.post(
      Uri.parse('$baseUrl/baiyunuser/account/login/v1'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': miniProgramUA,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('登录失败: HTTP ${response.statusCode}');
  }

  /// 获取门禁列表
  static Future<Map<String, dynamic>> getEntranceGuardList(String token, String loginUser) async {
    final body = {'pageNum': 0, 'pages': 0, 'pageSize': 0};

    final response = await http.post(
      Uri.parse('$baseUrl/baiyunuser/entranceguard/getList'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': miniProgramUA,
        'TOKEN': token,
        'LOGIN_USER': loginUser,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('获取门禁列表失败: HTTP ${response.statusCode}');
  }
}
