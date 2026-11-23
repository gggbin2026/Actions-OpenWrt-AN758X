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
     '本版已移除（factory / recovery / clients / netmode）；光猫管理只保留 ONU 菜单'),
    ('USB 打印服务', 'p910nd' in sel and 'luci-app-usb-printer' in sel,
     'p910nd + LuCI 界面 + 中文 + 全套 USB 内核模块'),
    ('PassWall 独占 DNS', 'chinadns-ng' in sel and 'luci-app-passwall' in sel and 'smartdns' not in sel,
     'SmartDNS 整组已剔除；dns_shunt=chinadns-ng + dns_redirect=1，53 由 PassWall 接管；dnsmasq 只留 DHCP/缓存'),
    ('rtp2httpd v3.17.2', 'rtp2httpd' in sel and 'luci-app-rtp2httpd' in sel,
     'RTP/UDP/RTSP → HTTP 流，FCC 毫秒级换台，带 LuCI 界面与简体中文'),
    ('DDNS 仅花生壳', 'ddns-scripts-services' in sel and 'lucky' not in sel,
     'Lucky 整组已移除；出厂仅一条 oray 配置，首启清掉其余 93 个 provider，LuCI 下拉只剩 oray.com'),
    ('编译期精简 + 发布压缩', on('CONFIG_STRIP_KERNEL_EXPORTS') and on('CONFIG_USE_MKLIBS'),
     'squashfs block 1024 KiB / strip 内核导出符号 / mklibs；Release 附件另打成 .tar.zst'),
    ('组播双代理 + IGMP Snooping',
     'omcproxy' in sel and 'igmpproxy' in sel and 'luci-app-igmpproxy' in sel
     and 'fastnet' in sel and 'homebox' not in sel,
     '用户复核：omcproxy(MLD/IGMPv3) + igmpproxy(IPv4) 两个都保留；IGMP Snooping 由 99-zz-igmp-snooping 首启开启；测速=FastNet、DDNS=花生壳、代理=PassWall'),
    ('iStore 软件中心', 'luci-app-store' in sel,
     '本版已移除；用 FastNet + `luci-app-package-manager`（apk 界面）替代'),
    ('nftables 防火墙', 'firewall4' in sel, 'fw4 + kmod-nft-*，不引入 iptables'),
    ('内核 6.18', on('CONFIG_LINUX_6_18'), 'KERNEL_PATCHVER 6.18'),
    ('apk + 全量签名', on('CONFIG_USE_APK') and on('CONFIG_SIGNED_PACKAGES'),
     '替代 opkg，包与固件均签名'),
    ('IPv6 关闭', off('CONFIG_IPV6') and off('CONFIG_KERNEL_IPV6'),
     '内核栈与 LuCI IPv6 上游全关'),
    ('简体中文', on('CONFIG_LUCI_LANG_zh_Hans'), '带 po 的 LuCI 包自动生成 zh-cn 中文包'),
    ('ARGON 主题', 'luci-theme-argon' in sel, '默认主题；bootstrap 是 LuCI 基础主题保留作 fallback（不是重复插件）'),
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
        'luci-app-airoha-npu', 'luci-app-natmode']),  # feed 4 包已移除，见 config 3.1 段
    ('网络 / 代理 / DNS', [
        'luci-app-passwall', 'luci-app-openclash', 'luci-app-mosdns',
        'luci-app-nft-qos', 'luci-app-ddns',
        'luci-app-tailscale', 'luci-app-easytier',
        'luci-app-fastnet']),
    ('系统 / 工具 / 管控', [
        'luci-app-ttyd', 'luci-app-watchdog', 'luci-app-taskplan',
        'luci-app-accesscontrol-plus', 'luci-app-vantage',
        'luci-app-package-manager', 'luci-app-firewall', 'luci-app-poweroffdevice',
        'luci-app-owq-wol', 'luci-app-accesscontrol']),
    ('USB 打印', ['luci-app-usb-printer', 'luci-app-p910nd']),
    ('主题 / 包管理', [
        'luci-app-package-manager', 'luci-theme-argon', 'luci-theme-bootstrap',
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
    'p910nd', 'xray-core', 'sing-box', 'chinadns-ng', 'dns2socks', 'rtp2httpd',
    'ddns-scripts', 'ddns-scripts-services', 'fastnet', 'linkease-app-entry',
    'luci-lib-linkeaseauth', 'nft-qos', 'nftables', 'taskd',
    'ttyd', 'watchdog', 'bash', 'snmpd-nossl',
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
out.write('3. **本版已移除 `naoki66/luci-app-airoha` feed**（factory / recovery / clients / '
           'netmode 四个页面）与 iStore 软件中心：光猫注册、LOID、IPTV、语音一律用 '
           '「ONU」顶级菜单；装包用 FastNet + `luci-app-package-manager`（apk 界面）。'
            '**本版做了插件去重，但组播代理按用户要求两个都保留**：'
            '`omcproxy` + `igmpproxy` / `luci-app-igmpproxy` 全在；测速只留 `FastNet`，'
            '`Homebox` 整组移除。另新增 **IGMP Snooping**（首启自动开启）。\n')
out.write('4. 保留的 `luci-app-natmode` 是 **NAT 类型**切换，与被移除的 `luci-app-netmode` '
           '（AP / DHCP / PPPoE）不是同一个包；PON 光猫上别随手切桥接/AP，会影响 WAN。'
           '`luci-app-airoha-npu` 是 NPU/CPU/PPE 状态页（只读监控），不属于已移除的 feed。\n')
out.write('5. 刷完核对：LuCI 有「ONU」顶级菜单、「服务 → USB 打印」、ARGON 主题仍生效；'
           '「服务 → 动态 DNS」里只有 `oray` 一条（默认禁用），'
           '服务商下拉**只剩 `oray.com`**；「服务 → rtp2httpd」菜单存在，'
            '「服务 → IGMP Proxy」菜单也在（组播双代理都保留）。'
            '**Homebox / Lucky / SmartDNS / OpenClash / MosDNS / Tailscale / '
            'EasyTier 菜单本版均已移除**（插件去重），属正常，不是编译失败。'
            'SSH 核对 Snooping：`uci get network.@device[0].igmp_snooping` 应为 `1`，'
            '`cat /sys/class/net/br-lan/bridge/multicast_snooping` 应为 `1`'
            '（首启时 br-lan 未建属正常，`logread -e igmp-snoop` 有提示）。\n')
out.write('6. **DNS 全交 PassWall，系统自带 DNS 已剔除**：SmartDNS 三个包整组退出，'
           '`99-zz-passwall-dns` 清空了 dnsmasq 的三条国内上游 / `noresolv` / '
           '`strictorder`，dnsmasq 只保留 DHCP 与缓存（**包本身不能删，LAN 和 PassWall '
           '都依赖它**）。PassWall 设 `dns_shunt=chinadns-ng` + `dns_redirect=1`，'
           '53 由它的 dnsmasq 实例接管、`chinadns-ng` 做国内外智能分流。'
           '`chinadns-ng` 已编入固件（PassWall 的 LUCI_DEPENDS 自带，config 里也显式 `=y`）。'
           '**未启用 PassWall 时**系统 dnsmasq 回落到 WAN 下发的 DNS，不会断网；'
           '一启用代理就整套接管。别再手填 `127.0.0.1#6053` 之类旧地址。\n')
out.write('7. **PassWall 首页的 TCP / UDP / DNS / HAPROXY「未运行」是未配置节点时的正常状态**，'
           '不是固件故障；「阿里 / 谷歌 / GitHub / YouTube 连接」是浏览器**直连**延迟测试，'
           'GitHub 显示连接失败只说明直连不通。用起来分三步：'
           '「节点订阅 → 添加订阅并更新」→「节点列表 → 选节点」→「基本设置 → 勾选启用」。'
           '固件已带 `xray-core` / `sing-box` 内核，HAPROXY 默认 N/A（负载均衡未开）。\n')
out.write('8. **DDNS 只有花生壳（oray.com）**：另一个 DDNS 客户端 `lucky` 整组已移除'
           '（连带它的 socat 端口转发 / HTTP 反代也没了，需要的话把 config 三行加回来即可）。'
           '保留 `ddns-scripts` 引擎 + `luci-app-ddns` 界面 + `ddns-scripts-services`'
           '（`oray.com.json` 在这个包里，是 `ddns-scripts` 的硬依赖，不能整包删）。'
           'LuCI「服务 → 动态 DNS」编辑 `oray` 那条，把 `username` / `password` '
           '换成 Oray 账号与花生壳管理密码，`lookup_host` / `domain` 换成贝锐给的免费域名'
           '（`xxx.oray.net`），把 `enabled` 改成 `1`，保存并应用即可。\n'
           '⚠ 服务商字段必须是 `oray.com`（不是 `oray`）；固件 IPv6 已关，不要加 IPv6 段。'
           '首启脚本 `99-zz-ddns-only-oray` 会删掉 `/usr/share/ddns/default/` 下其余 93 个 '
           'provider json，所以**服务商下拉只剩 `oray.com`**（外加一个 custom 选项）——'
           '这是「只留花生壳」的实现方式。代价：`apk --check` 会报那 93 个文件缺失'
           '（overlay whiteout），但 LuCI / ddns 服务完全不受影响。\n')
out.write('9. **rtp2httpd v3.17.2**：把组播 RTP/UDP/RTSP 转成 HTTP 单播流，'
           '带 FCC 快速换台。在「服务 → rtp2httpd」配置组播源与监听端口；'
            'IPTV 场景配合「ONU 菜单」的 IGMP 设置 + 组播双代理 '
            '（`igmpproxy` 管 IPv4 直放、`omcproxy` 管 MLD/IGMPv3）+ '
            'IGMP Snooping 使用；**两个代理别同时在同一上行接口启用**.'
           '源码来自 `stackia/rtp2httpd` main 的 `openwrt-support/`，'
           '用 `Makefile.versioned` 固定版本 + PKG_HASH 从 GitHub Release 拉源码，'
           'Web UI 已预构建，不需要 Node/pnpm。\n')
out.write('10. **固件附件已压缩**：Release 只传一个 `ponwrt-<机型>-firmware.tar.zst`'
           '（无 zstd 时回退 `.tar.gz`）+ manifest / profiles.json / sha256sums。'
           '下载后 `tar -I zstd -xf <包名>.tar.zst`（或 `tar -xzf`）解压出 '
           '`*-squashfs-sysupgrade.itb` 再刷；**裸 `.itb` 不传 Release**，'
           '在本次 run 的 Artifacts 里保留，供 owut / 调试用。'
           '裸镜像仍可能 80+ MB，压缩包才是下载用的那份。\n\n')
out.write('## 八、这个 Release 会保留多久\n\n')
out.write('- GitHub Release **本身没有过期时间**，下载链接长期有效；\n')
out.write('- 为控制仓库体积，本仓库**只保留最近 %s 次成功发布的固件 Release**，'
          '第 %s 个及更早的会被自动删除（只删 `fw-` 前缀，'
          '工具链缓存 Release `cache-backup` 不受影响）；\n' % (keep, str(int(keep) + 1)))
out.write('- 想留某一版：在它被自动清理前，把附件下载到本地；\n')
out.write('- 同次编译的 Artifact 另存 90 天，里面是**未压缩的裸固件**，'
           'Release 只放 `.tar.zst` 压缩包以省空间；\n')
out.write('- workflow run 日志默认不删除，便于倒查。\n')
out.write('\n---\n')
out.write('本次 tag：`%s` · 适用光猫：%s\n' % (tag, dev_cn))
out.close()

print('✅ Release 说明已生成，实读 .config: %d 个 =y 包' % len(sel))
