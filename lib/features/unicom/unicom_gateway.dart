import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'unicom_crypto.dart';

/// Unicom 网关直连 — 对齐 zlt.py 的 UnicomLogin
/// 发码: /mobileService/sendRadomNum.htm  登录: /mobileService/radomLogin.htm
class UnicomSendResult {
  final bool success;
  final String message;
  UnicomSendResult(this.success, {this.message = ''});
}

class UnicomTokenResult {
  final bool success;
  final String message;
  final String tokenOnline;
  final String ecsToken;
  final String appId;
  final String deviceId;

  UnicomTokenResult(
    this.success, {
    this.message = '',
    this.tokenOnline = '',
    this.ecsToken = '',
    this.appId = '',
    this.deviceId = '',
  });
}

class UnicomGateway {
  static const String _host = 'm.client.10010.com';
  static const String _uaPrefix =
      'Mozilla/5.0 (Linux; Android 13; LE2100 Build/TP1A.220905.001; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
      'Chrome/103.0.5060.129 Mobile Safari/537.36';
  static const String _appIdSuffix =
      '912d306b5053abf90c7ebbb695887bc870ae0706d573c348539c26c5c0a87864'
      '1fcc0d3e90acb9be1e6ef858a59af546f3c826988332376b7d18c8ea2398e'
      'e3a9c3db947e2471d32a49612';

  final String phone;
  late final String deviceId;
  late final String appId;

  final HttpClient _client = HttpClient();

  UnicomGateway(this.phone) {
    deviceId = _uuidHex();
    appId = _buildAppId();
  }

  String get userAgent =>
      '$_uaPrefix unicom{version:android@10.0100,desmobile:$phone};'
      'devicetype{deviceBrand:OnePlus,deviceModel:LE2100};{yw_code:}';

  /// 下发短信验证码
  Future<UnicomSendResult> sendSmsCode() async {
    final body = <String>[
      'isFirstInstall=1',
      'resultToken=',
      'provinceCode=051',
      'cityCode=520',
      'deviceOS=android13',
      'mobile=${_urlSafe(_encrypt(phone))}',
      'netWay=Wifi',
      'loginCodeLen=6',
      'version=${_urlSafe('android@10.0600')}',
      'deviceCode=$deviceId',
      'deviceId=$deviceId',
      'pip=192.168.2.125',
      'keyVersion=',
      'send_flag=',
      'provinceChanel=general',
      'appId=$appId',
      'deviceModel=V1936A',
      'androidId=${_uuidHex().substring(8, 24)}',
      'deviceBrand=',
      'timestamp=${_timestamp()}',
    ].join('&');

    try {
      final data = await _post('/mobileService/sendRadomNum.htm', body);
      final code = (data['code'] ?? '').toString();
      if (code.isEmpty || code == '0' || code == '0000') {
        return UnicomSendResult(true);
      }
      return UnicomSendResult(false, message: _messageOf(data, '验证码下发失败'));
    } catch (e) {
      return UnicomSendResult(false,
          message: e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// 短信验证码登录，取 token_online / ecs_token
  Future<UnicomTokenResult> login(String smsCode) async {
    final body = <String>[
      'isFirstInstall=1',
      'simCount=1',
      'yw_code=',
      'loginStyle=0',
      'isRemberPwd=true',
      'deviceOS=android13',
      'mobile=${_urlSafe(_encrypt(phone))}',
      'netWay=Wifi',
      'version=${_urlSafe('android@10.0100')}',
      'deviceId=$deviceId',
      'password=${_urlSafe(_encrypt(smsCode))}',
      'keyVersion=',
      'provinceChanel=general',
      'appId=$appId',
      'deviceModel=V1936A',
      'androidId=${_uuidHex().substring(8, 24)}',
      'deviceBrand=',
      'timestamp=${_timestamp()}',
    ].join('&');

    try {
      final data = await _post('/mobileService/radomLogin.htm', body);
      final tokenOnline = (data['token_online'] ?? '').toString();
      final ecsToken = (data['ecs_token'] ?? '').toString();
      if (tokenOnline.isEmpty && ecsToken.isEmpty) {
        return UnicomTokenResult(false,
            message: _messageOf(data, '登录失败，请检查短信验证码'),
            appId: appId,
            deviceId: deviceId);
      }
      return UnicomTokenResult(
        true,
        tokenOnline: tokenOnline,
        ecsToken: ecsToken,
        appId: appId,
        deviceId: deviceId,
      );
    } catch (e) {
      return UnicomTokenResult(false,
          message: e.toString().replaceFirst('Exception: ', ''),
          appId: appId,
          deviceId: deviceId);
    }
  }

  Future<Map<String, dynamic>> _post(String path, String body) async {
    final req = await _client
        .postUrl(Uri.parse('https://$_host$path'))
        .timeout(const Duration(seconds: 20));
    req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh-Hans;q=0.9');
    req.headers.set(HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded; charset=UTF-8');
    req.add(utf8.encode(body));
    final resp = await req.close().timeout(const Duration(seconds: 20));
    final text = await resp.transform(utf8.decoder).join();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 与 Python quote() 对齐：保留 /，仅转义 + 与 =
  static String _urlSafe(String s) =>
      s.replaceAll('+', '%2B').replaceAll('=', '%3D');

  static String _encrypt(String value) => UnicomCrypto.encryptBase64(value);

  static String _messageOf(Map<String, dynamic> data, String fallback) {
    for (final k in ['msg', 'message', 'desc', 'resultMsg']) {
      final v = (data[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  static String _uuidHex() {
    final r = Random.secure();
    return List.generate(32, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
  }

  /// 对齐脚本：randint(0,10) 拼接固定尾巴
  static String _buildAppId() {
    final r = Random.secure();
    String d() => r.nextInt(11).toString();
    return '${d()}f${d()}af${d()}${d()}ad${d()}$_appIdSuffix';
  }

  static String _timestamp() {
    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${p(now.month)}${p(now.day)}'
        '${p(now.hour)}${p(now.minute)}${p(now.second)}';
  }

  void dispose() {
    _client.close();
  }
}
