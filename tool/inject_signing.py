#!/usr/bin/env python3
"""CI 专用：注入 Android 签名配置到 build.gradle.kts

Flutter 3.41.x 模板本身不含 signingConfigs 块（只有
signingConfig = signingConfigs.getByName("debug")），所以判重不能用
'signingConfigs' 关键字，否则注入会被永久跳过、release 包一直是 debug 签名。
这里改用注入标记 "qiaoba.keystore" 判重，并兼容模板将来自带 signingConfigs 的情况。
"""
import os
import re

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

target = 'android/app/build.gradle.kts'
with open(target, 'r', encoding='utf-8') as f:
    c = f.read()

MARK = 'qiaoba.keystore'

RELEASE_BLOCK = '''        create("release") {
            val ksFile = file("%s")
            if (ksFile.exists()) {
                storeFile = ksFile
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
                keyAlias = System.getenv("KEYSTORE_ALIAS") ?: ""
                keyPassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
            }
        }
''' % MARK

if MARK in c:
    print('[SKIP] signing already injected')
else:
    # 1. release buildType 改为条件签名：有 keystore 用 release，否则回落 debug
    c = c.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = if (file("%s").exists()) '
        'signingConfigs.getByName("release") else signingConfigs.getByName("debug")' % MARK,
        1)

    # 2. 注入 signingConfigs 块（模板自带该块时插入其内部，避免重复定义）
    if re.search(r'^\s*signingConfigs\s*\{', c, re.M):
        c = re.sub(r'(^\s*signingConfigs\s*\{\n)', r'\1' + RELEASE_BLOCK, c, count=1, flags=re.M)
    else:
        block = '    signingConfigs {\n' + RELEASE_BLOCK + '    }\n\n'
        c = re.sub(r'(    buildTypes\s*\{)', block + r'\1', c, count=1)

    with open(target, 'w', encoding='utf-8') as f:
        f.write(c)
    print('[OK] signing config injected')
