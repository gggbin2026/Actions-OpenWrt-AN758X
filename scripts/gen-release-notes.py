#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen-release-notes.py —— 从本次编译的最终 .config 实读，往 release.txt 追加
「内置插件」一段。

2026-11-23 精简：用户要求下载页只要「路由器名字 / 插件信息 /
账户密码 IP 配置」等信息。原来的「做了哪些配置」「刷机必读 10 条」
「保留策略」「中文包全表」「关键服务全表」「刷机条款长文」全部移除；
机型/固件名/出厂默认/校验由 workflow 的 shell 段写好，本脚本只续写插件表。

环境变量：
  BUILD_ROOT        PonWrt 源码根目录（其下 openwrt/.config 即最终配置）
  RELEASE_TXT      要追加的 release.txt 绝对路径
  PROFILE          机型 profile（仅用于兜底）
"""

import os
import re

cfg_path = os.path.join(os.environ['BUILD_ROOT'], 'openwrt', '.config')
with open(cfg_path, encoding='utf-8', errors='replace') as f:
    cfg = f.read()

sel = set(re.findall(r'^CONFIG_PACKAGE_([A-Za-z0-9_.+-]+)=y', cfg, re.M))
out = open(os.environ['RELEASE_TXT'], 'a', encoding='utf-8')

groups = [
    ('PON / 光猫', [
        'luci-app-onu', 'luci-app-pon', 'luci-app-iptv', 'luci-app-pon-status',
        'luci-app-igmpproxy', 'luci-app-rtp2httpd']),
    ('Airoha 硬件 / 状态', ['luci-app-airoha-npu', 'luci-app-natmode']),
    ('网络 / 代理 / DNS', [
        'luci-app-passwall', 'luci-app-openclash', 'luci-app-mosdns',
        'luci-app-nft-qos', 'luci-app-ddns', 'luci-app-tailscale',
        'luci-app-easytier', 'luci-app-fastnet']),
    ('系统 / 工具 / 管控', [
        'luci-app-ttyd', 'luci-app-watchdog', 'luci-app-taskplan',
        'luci-app-accesscontrol-plus', 'luci-app-vantage',
        'luci-app-package-manager', 'luci-app-firewall',
        'luci-app-poweroffdevice', 'luci-app-owq-wol', 'luci-app-accesscontrol']),
    ('内网测速', ['luci-app-homebox']),
    ('USB 打印', ['luci-app-usb-printer', 'luci-app-p910nd']),
    ('主题 / 包管理', [
        'luci-app-package-manager', 'luci-theme-argon', 'luci-theme-bootstrap',
        'luci-theme-fluent', 'luci-theme-kucat']),
]

out.write('\n## 内置插件\n\n')
out.write('| 分类 | 本次编入的 LuCI 包 |\n|------|--------------------|\n')
listed = set()
for gname, pkgs in groups:
    hit = [p for p in pkgs if p in sel]
    listed.update(hit)
    if hit:
        out.write('| %s | %s |\n' % (gname, ' '.join('`%s`' % p for p in hit)))
other = sorted(p for p in sel
               if (p.startswith('luci-app-') or p.startswith('luci-theme-')
                   or p.startswith('luci-mod-')) and p not in listed)
if other:
    out.write('| 其他 | %s |\n' % ' '.join('`%s`' % p for p in other))

i18n = sorted(p for p in sel if p.startswith('luci-i18n-') and p.endswith('-zh-cn'))
bodies = [
    'airoha-pond', 'airoha-ponctl', 'airoha-pon-debug', 'omcproxy', 'igmpproxy',
    'homebox', 'p910nd', 'xray-core', 'sing-box', 'chinadns-ng', 'dns2socks', 'rtp2httpd',
    'ddns-scripts', 'ddns-scripts-services', 'fastnet', 'linkease-app-entry',
    'ttyd', 'watchdog', 'bash', 'snmpd-nossl', 'kmod-usb-printer', 'curl',
]
bhit = [p for p in bodies if p in sel]
out.write('\n')
stars = ' '.join('`%s`' % p for p in bhit[:6]) if bhit else '（无）'
out.write('- 简体中文包：`%d` 个；关键服务 `%d` 个：%s%s\n' % (
    len(i18n), len(bhit), stars, ' 等' if len(bhit) > 6 else ''))
out.write('- 完整变更与发布记录见仓库 `固件发布日志.md` / `RELEASES.md`。\n')
out.write('\n')
out.close()
print('✅ Release 说明已追加插件表，实读 .config: %d 个 =y 包' % len(sel))
