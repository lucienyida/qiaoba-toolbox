/// 联通掌厅 RSA 工具 — 对齐 zlt.py 的 RSA_Encrypt
/// 公钥 SPKI(base64) → PKCS#1 v1.5 填充 → 117 字节分块 → base64 输出
import 'dart:convert';
import 'dart:math';

class UnicomCrypto {
  static const String rsaPubkeyPem =
      'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDc+CZK9bBA9IU+gZUOc6FUGu7y'
      'O9WpTNB0PzmgFBh96Mg1WrovD1oqZ+eIF4LjvxKXGOdI79JRdve9NPhQo07+uqGQ'
      'gE4imwNnRx7PFtCRryiIEcUoavuNtuRVoBAm6qdB0SrctgaqGfLgKvZHOnwTjyNq'
      'jBUxzMeQlEC2czEMSwIDAQAB';

  static final List<BigInt> _key = _parsePublicKey();

  static BigInt get modulus => _key[0];
  static BigInt get exponent => _key[1];

  /// 加密并 base64（服务端要求先 URL 编码，见 UnicomGateway._urlSafe）
  static String encryptBase64(String plain) {
    final bytes = utf8.encode(plain);
    final k = (modulus.bitLength + 7) ~/ 8;
    final chunk = k - 11; // PKCS#1 v1.5 单块上限 117
    final out = <int>[];
    for (var offset = 0; offset < bytes.length; offset += chunk) {
      final end = offset + chunk < bytes.length ? offset + chunk : bytes.length;
      out.addAll(_encryptBlock(bytes.sublist(offset, end), k));
    }
    return base64.encode(out);
  }

  static List<int> _encryptBlock(List<int> msg, int k) {
    // EM = 0x00 || 0x02 || PS(非零随机, 长度 ≥ 8) || 0x00 || M
    final rng = Random.secure();
    final psLen = k - 3 - msg.length;
    if (psLen < 8) throw Exception('RSA 明文过长');
    final ps = List<int>.generate(psLen, (_) {
      int b;
      do {
        b = rng.nextInt(256);
      } while (b == 0);
      return b;
    });

    final em = <int>[0x00, 0x02, ...ps, 0x00, ...msg];
    final m = BigInt.parse(_bytesToHex(em), radix: 16);
    final c = m.modPow(exponent, modulus);

    var hex = c.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final cb = _hexToBytes(hex);

    // 左侧补零到模长，保证定长输出
    final block = List<int>.filled(k, 0);
    block.setRange(k - cb.length, k, cb);
    return block;
  }

  /// DER: SEQUENCE { SEQ{OID,NULL}, BIT STRING { SEQ{ INTEGER n, INTEGER e } } }
  static List<BigInt> _parsePublicKey() {
    final bytes = base64.decode(rsaPubkeyPem);
    final p = _Asn1Parser(bytes);
    p.readTag(); // SEQUENCE
    p.readLength();
    p.readTag(); // SEQUENCE (AlgorithmIdentifier)
    p.skip(p.readLength());
    p.readTag(); // BIT STRING
    p.readLength();
    p.skip(1); // unused-bits
    p.readTag(); // SEQUENCE (RSAPublicKey)
    p.readLength();
    p.readTag(); // INTEGER n
    final nBytes = p.readIntegerBytes();
    p.readTag(); // INTEGER e
    final eBytes = p.readIntegerBytes();
    return [
      BigInt.parse(_bytesToHex(nBytes), radix: 16),
      BigInt.parse(_bytesToHex(eBytes), radix: 16),
    ];
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}

/// 极简 DER 解析器
class _Asn1Parser {
  final List<int> bytes;
  int pos = 0;

  _Asn1Parser(this.bytes);

  int readTag() => bytes[pos++];

  int readLength() {
    var len = bytes[pos++];
    if (len & 0x80 != 0) {
      final numBytes = len & 0x7f;
      len = 0;
      for (var i = 0; i < numBytes; i++) {
        len = (len << 8) | bytes[pos++];
      }
    }
    return len;
  }

  void skip(int n) => pos += n;

  List<int> readIntegerBytes() {
    final len = readLength();
    var start = pos;
    var realLen = len;
    while (realLen > 0 && bytes[start] == 0) {
      start++;
      realLen--;
    }
    final out = bytes.sublist(start, start + realLen);
    pos += len;
    return out;
  }
}
