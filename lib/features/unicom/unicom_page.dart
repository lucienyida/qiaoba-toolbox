import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'unicom_gateway.dart';
import 'unicom_history_store.dart';

/// 取 Token 页面 — 网关短信登录直连
class UnicomPage extends StatefulWidget {
  const UnicomPage({super.key});

  @override
  State<UnicomPage> createState() => _UnicomPageState();
}

class _UnicomPageState extends State<UnicomPage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  UnicomGateway? _gateway;
  UnicomTokenResult? _result;

  bool _sending = false;
  bool _logging = false;
  int _countdown = 0;
  Timer? _timer;

  List<UnicomHistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _gateway?.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await UnicomHistoryStore.load();
    if (mounted) setState(() => _history = list);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _copy(String text, [String msg = '已复制']) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast(msg);
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 11 || !phone.startsWith('1')) {
      _toast('请输入正确的 11 位手机号');
      return;
    }
    setState(() => _sending = true);
    try {
      _gateway?.dispose();
      _gateway = UnicomGateway(phone);
      final res = await _gateway!.sendSmsCode();
      if (res.success) {
        _toast('✅ 验证码已下发');
        _startCountdown();
      } else {
        _toast('❌ ${res.message}');
      }
    } catch (e) {
      _toast('❌ ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _doLogin() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (phone.length != 11 || !phone.startsWith('1')) {
      _toast('请输入正确的 11 位手机号');
      return;
    }
    if (code.isEmpty) {
      _toast('请输入短信验证码');
      return;
    }
    setState(() => _logging = true);
    try {
      // 复用发码时的 appId/deviceId，仅在手机号变更时重建，保证设备指纹一致
      if (_gateway == null || _gateway!.phone != phone) {
        _gateway?.dispose();
        _gateway = UnicomGateway(phone);
      }
      final res = await _gateway!.login(code);
      if (!res.success) {
        _toast('❌ ${res.message}');
        return;
      }
      setState(() => _result = res);
      await UnicomHistoryStore.save(UnicomHistoryItem(
        phone: phone,
        tokenOnline: res.tokenOnline,
        ecsToken: res.ecsToken,
        appId: res.appId,
        at: DateTime.now().millisecondsSinceEpoch,
      ));
      await _loadHistory();
      _toast('🎉 已获取 token_online');
    } catch (e) {
      _toast('❌ ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDark(context);
    ThemeController.applySystemOverlay(isDark);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark ? AppTheme.darkCard : Colors.white,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        appBar: AppBar(
          systemOverlayStyle: overlayStyle,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF5A5F), AppTheme.unicomColor]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.sim_card_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 10),
            const Text('取 Token'),
          ]),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _buildInputCard(isDark),
            const SizedBox(height: 16),
            if (_result != null) _buildResultCard(isDark),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildHistory(isDark),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildInputCard(bool isDark) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('手机号', isDark),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  decoration: const InputDecoration(
                      hintText: '请输入手机号', counterText: ''),
                ),
                const SizedBox(height: 12),
                _label('短信验证码', isDark),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          hintText: '短信收到的验证码', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: (_sending || _countdown > 0) ? null : _sendCode,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(110, 48)),
                    child: Text(
                      _sending
                          ? '发送中...'
                          : (_countdown > 0 ? '${_countdown}s' : '获取验证码'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _logging ? null : _doLogin,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.unicomColor),
                  child: _logging
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('获取 Token'),
                ),
                const SizedBox(height: 10),
                Text('验证码由官方客户端下发，本工具仅做登录请求转发',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.darkTextMuted
                            : AppTheme.lightTextMuted)),
              ]),
        ),
      );

  Widget _label(String text, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkTextMain : const Color(0xFF334155))),
      );

  Widget _fieldBox(String title, String value, bool isDark,
          {VoidCallback? onCopy}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: isDark ? AppTheme.darkInputFill : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)),
            if (onCopy != null)
              GestureDetector(
                onTap: onCopy,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.unicomColor.withOpacity(0.2)
                          : AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('复制',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.unicomColor)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          SelectableText(value.isEmpty ? '-' : value,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: isDark ? AppTheme.darkTextMain : AppTheme.lightTextMain,
                  height: 1.4)),
        ]),
      );

  Widget _buildResultCard(bool isDark) {
    final r = _result!;
    final all = 'token_online=${r.tokenOnline}\n'
        'ecs_token=${r.ecsToken}\n'
        'appId=${r.appId}\n'
        'deviceId=${r.deviceId}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle,
                    color: AppTheme.success, size: 22),
                const SizedBox(width: 6),
                Text('获取成功',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppTheme.darkTextMain
                            : AppTheme.lightTextMain)),
              ]),
              const SizedBox(height: 16),
              _fieldBox('token_online', r.tokenOnline, isDark,
                  onCopy: () => _copy(r.tokenOnline, 'token_online 已复制')),
              _fieldBox('ecs_token', r.ecsToken, isDark,
                  onCopy: () => _copy(r.ecsToken, 'ecs_token 已复制')),
              _fieldBox('appId', r.appId, isDark,
                  onCopy: () => _copy(r.appId, 'appId 已复制')),
              _fieldBox('deviceId', r.deviceId, isDark,
                  onCopy: () => _copy(r.deviceId, 'deviceId 已复制')),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => _copy(all, '全部凭证已复制'),
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('复制全部', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44)),
              ),
            ]),
      ),
    );
  }

  Widget _buildHistory(bool isDark) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.history,
                      size: 18, color: AppTheme.unicomColor),
                  const SizedBox(width: 8),
                  Text('历史记录',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppTheme.darkTextMain
                              : AppTheme.lightTextMain)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await UnicomHistoryStore.clear();
                      await _loadHistory();
                      _toast('已清空历史');
                    },
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32)),
                    child: const Text('清空',
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.danger)),
                  ),
                ]),
                const SizedBox(height: 4),
                ..._history.map((i) => _buildHistoryItem(i, isDark)),
              ]),
        ),
      );

  Widget _buildHistoryItem(UnicomHistoryItem item, bool isDark) {
    final dt = DateTime.fromMillisecondsSinceEpoch(item.at);
    String p(int n) => n.toString().padLeft(2, '0');
    final timeStr =
        '${dt.year}/${p(dt.month)}/${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () {
              _phoneCtrl.text = item.phone;
              _toast('已填入手机号: ${item.phone}');
            },
            child: Text(item.phone,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppTheme.darkTextMain
                        : AppTheme.lightTextMain)),
          ),
          const Spacer(),
          Text(timeStr,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppTheme.darkTextMuted
                      : AppTheme.lightTextMuted)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              await UnicomHistoryStore.delete(item.phone);
              await _loadHistory();
              _toast('已删除: ${item.phone}');
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFECACA))),
              child: const Icon(Icons.close, size: 14, color: AppTheme.danger),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _copy(item.tokenOnline, 'token_online 已复制'),
          child: SelectableText(
              item.tokenOnline.isEmpty ? '-' : item.tokenOnline,
              maxLines: 2,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: isDark
                      ? AppTheme.darkTextSub
                      : AppTheme.lightTextSub)),
        ),
      ]),
    );
  }
}
