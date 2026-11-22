#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen-release-notes.py —— 从本次编译的最终 .config 实读，追加 Release 说明的
「做了哪些配置 / 内置插件清单 / 刷机必读 / 保留策略」四段。

由 .github/workflows/build-ponwrt.yml 的 "Generate release tag and notes" 调用；
前半段（固件名称、适用光猫、编译信息、文件清单、SHA256）由 shell 写好，
本脚本以 append 方式续写，不覆盖。

需要的环境变量：
  BUILD_ROOT        PonWrt 源码根目录（其下 openwrt/.config 即最终配置）
  RELEASE_TXT      要追加的 release.txt 绝对路径
  PROFILE          机型 profile
  DEV_CN           机型中文名
  RELEASE_TAG      本次 Release tag
  KEEP_FW_RELEASES 固件 Release 保留次数
"""

import os
import re

cfg_path = os.path.join(os.environ['BUILD_ROOT'], 'openwrt', '.config')
with open(cfg_path, encoding='utf-8', errors='replace') as f:
    cfg = f.read()

sel = set(re.findall(r'^CONFIG_PACKAGE_([A-Za-z0-9_.+-]+)=y', cfg, re.M))


def on(sym):
    """顶层 CONFIG_ 符号是否为 =y（允许行尾注释 / 尾随空白）"""
    return re.search(r'^' + re.escape(sym) + r'=y(?:\s*(?:#.*)?)?$', cfg, re.M) is not None


def off(sym):
    """顶层 CONFIG_ 符号是否显式写成 '# ... is not set'（允许尾注释）"""
    return re.search(r'^# ' + re.escape(sym) + r' is not set(?:\s*(?:#.*)?)?$', cfg, re.M) is not None


dev_cn = os.environ.get('DEV_CN', os.environ.get('PROFILE', ''))
tag = os.environ.get('RELEASE_TAG', '')
keep = os.environ.get('KEEP_FW_RELEASES', '5')

out = open(os.environ['RELEASE_TXT'], 'a', encoding='utf-8')

# ---------------------------------------------------------------- 配置摘要
out.write('## 五、做了哪些配置\n\n')
out.write('> 以下每一项都从本次编译的 `.config` 读取，`✅` = 确实编进去了。\n\n')
out.write('| 配置项 | 状态 | 说明 |\n|--------|------|------|\n')
checks = [
    ('PON 光口驱动', on('CONFIG_TARGET_airoha'), 'Airoha AN758x PON 目标'),
    ('ONU 顶级菜单', 'luci-app-onu' in sel,
     '状态/身份/认证/上网/IPTV/语音/诊断（替代旧 luci-app-pon）'),
    ('PON 用户态', 'airoha-pond' in sel, 'OMCI+OAM 协议代理 / ponctl / pon-debug'),
    ('PON 光模块卡片', 'luci-app-pon-status' in sel, '概览页收发光/温度/电流/电压'),
    ('Airoha NPU 状态页', 'luci-app-airoha-npu' in sel,
     'NPU/CPU/Frame Engine/PPE 流表，带简体中文'),
    ('Airoha feed 扩展', 'luci-app-airoha-factory' in sel,
     '工厂信息/恢复/终端列表/网络模式'),
    ('USB 打印服务', 'p910nd' in sel and 'luci-app-usb-printer' in sel,
     'p910nd + LuCI 界面 + 中文 + 全套 USB 内核模块'),
    ('iStore 软件中心', 'luci-app-store' in sel, 'luci-app-store + taskd + luci-lib-*'),
    ('nftables 防火墙', 'firewall4' in sel, 'fw4 + kmod-nft-*，不引入 iptables'),
    ('内核 6.18', on('CONFIG_LINUX_6_18'), 'KERNEL_PATCHVER 6.18'),
    ('apk + 全量签名', on('CONFIG_USE_APK') and on('CONFIG_SIGNED_PACKAGES'),
     '替代 opkg，包与固件均签名'),
    ('IPv6 关闭', off('CONFIG_IPV6') and off('CONFIG_KERNEL_IPV6'),
     '内核栈与 LuCI IPv6 上游全关'),
    ('简体中文', on('CONFIG_LUCI_LANG_zh_Hans'), '带 po 的 LuCI 包自动生成 zh-cn 中文包'),
    ('ARGON 主题', 'luci-theme-argon' in sel, '默认主题；bootstrap / fluent 可共存'),
    ('PPE 硬件流卸载', 'kmod-nft-offload' in sel, 'nftables flow offload → PPE 硬件转发'),
]
for name, ok, desc in checks:
    out.write('| %s | %s | %s |\n' % (name, '✅' if ok else '—', desc))
out.write('\n')

# ------------------------------------------------------------ 内置插件清单
groups = [
    ('PON / 光猫', [
        'luci-app-onu', 'luci-app-pon', 'luci-app-iptv', 'luci-app-pon-status',
        'luci-app-igmpproxy', 'luci-app-rtp2httpd']),
    ('Airoha 硬件 / 状态', [
        'luci-app-airoha-npu', 'luci-app-natmode', 'luci-app-airoha-factory',
        'luci-app-airoha-recovery', 'luci-app-clients', 'luci-app-netmode',
        'luci-app-airoha-fancontrol', 'luci-app-mesh-conf']),
    ('网络 / 代理 / DNS', [
        'luci-app-passwall', 'luci-app-openclash', 'luci-app-mosdns',
        'luci-app-smartdns', 'luci-app-nft-qos', 'luci-app-ddns',
        'luci-app-lucky', 'luci-app-tailscale', 'luci-app-easytier',
        'luci-app-fastnet']),
    ('系统 / 工具 / 管控', [
        'luci-app-ttyd', 'luci-app-watchdog', 'luci-app-taskplan',
        'luci-app-accesscontrol-plus', 'luci-app-homebox', 'luci-app-vantage',
        'luci-app-package-manager', 'luci-app-firewall', 'luci-app-poweroffdevice',
        'luci-app-owq-wol', 'luci-app-accesscontrol']),
    ('USB 打印', ['luci-app-usb-printer', 'luci-app-p910nd']),
    ('应用商店 / 主题', [
        'luci-app-store', 'luci-theme-argon', 'luci-theme-bootstrap',
        'luci-theme-fluent', 'luci-theme-kucat']),
]
out.write('## 六、内置插件清单\n\n')
out.write('> 下表由 `.config` 中 `CONFIG_PACKAGE_luci-*=y` 实读生成；\n')
out.write('> 「拉了源码但本机型没勾选」的不在此表，以本表为准。\n\n')
out.write('| 分类 | 本次编入的 LuCI 包 |\n|------|--------------------|\n')
listed = set()
for gname, pkgs in groups:
    hit = [p for p in pkgs if p in sel]
    listed.update(hit)
    if hit:
        out.write('| %s | %s |\n' % (gname, ' '.join('`%s`' % p for p in hit)))
other = sorted(
    p for p in sel
    if (p.startswith('luci-app-') or p.startswith('luci-theme-')
        or p.startswith('luci-mod-')) and p not in listed
)
if other:
    out.write('| 其他 | %s |\n' % ' '.join('`%s`' % p for p in other))
out.write('\n')

i18n = sorted(p for p in sel if p.startswith('luci-i18n-') and p.endswith('-zh-cn'))
bodies = [
    'airoha-pond', 'airoha-ponctl', 'airoha-pon-debug', 'omcproxy', 'igmpproxy',
    'p910nd', 'xray-core', 'sing-box', 'smartdns', 'fastnet', 'linkease-app-entry',
    'luci-lib-linkeaseauth', 'ddns-scripts', 'nft-qos', 'nftables', 'taskd',
    'homebox', 'ttyd', 'lucky', 'watchdog', 'bash', 'snmpd-nossl',
    'kmod-usb-printer', 'curl', 'luci-compat',
]
bhit = [p for p in bodies if p in sel]
out.write('- **简体中文包**：共 `%d` 个%s\n' % (
    len(i18n),
    ('（' + '、'.join('`%s`' % p for p in i18n) + '）') if i18n else ''))
out.write('- **关键服务本体 / 依赖**：%s\n\n' % (
    ' '.join('`%s`' % p for p in bhit) if bhit else '（无）'))

# ------------------------------------------------------------ 刷机与保留策略
out.write('## 七、刷机前必读\n\n')
out.write('1. 用 `AN758x-Stock2UBI` 备份原厂 flash 与 **PON / 校准数据**，刷错可回退。\n')
out.write('2. 跨版本 sysupgrade **不要勾「保留配置」**：旧 `/etc/shadow` 会盖掉 '
          '`root/admin`，新旧 LuCI 缓存冲突还可能进不去后台；'
          '真进不去长按 reset 30 秒或进 U-Boot web 重刷。\n')
out.write('3. `luci-app-airoha-factory` 按 XR1710G 分区布局写的，'
          '**只读查看**，别点写入/保存；写错 MAC、SN 或 WiFi 校准会影响 PON 注册与无线。\n')
out.write('4. `luci-app-netmode` 能切 AP / DHCP / PPPoE，PON 光猫上别随手切到 AP。\n')
out.write('5. 刷完核对：LuCI 有「ONU」顶级菜单、「服务 → USB 打印」、ARGON 主题仍生效。\n\n')

out.write('## 八、这个 Release 会保留多久\n\n')
out.write('- GitHub Release **本身没有过期时间**，下载链接长期有效；\n')
out.write('- 为控制仓库体积，本仓库**只保留最近 %s 次成功发布的固件 Release**，'
          '第 %s 个及更早的会被自动删除（只删 `fw-` 前缀，'
          '工具链缓存 Release `cache-backup` 不受影响）；\n' % (keep, str(int(keep) + 1)))
out.write('- 想留某一版：在它被自动清理前，把附件下载到本地；\n')
out.write('- 同次编译的 Artifact 另存 90 天，workflow run 日志默认不删除，便于倒查。\n')
out.write('\n---\n')
out.write('本次 tag：`%s` · 适用光猫：%s\n' % (tag, dev_cn))
out.close()

print('✅ Release 说明已生成，实读 .config: %d 个 =y 包' % len(sel))
