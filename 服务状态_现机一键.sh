#!/bin/sh
# =============================================================
# PonWrt AN758x —— 服务状态现机救急（不用重编固件）
# SSH 进 192.168.1.1 后整段粘贴，或 scp 上去 sh 服务状态_现机一键.sh
# 幂等：可重复执行。
#
# 本版对应「剔除系统 DNS，只要 PassWall」：
#   1) 清空 dnsmasq 的自定义上游（系统自带 DNS 配置）
#   2) PassWall 设为 chinadns-ng + dns_redirect=1，独占 53
#   3) 花生壳 oray.com DDNS 配置提示
#   5) 组播双代理 / IGMP Snooping / rtp2httpd 复查
#   5) 打印自检
# =============================================================
set -u

echo "==================== 1) 剔除系统自带 DNS 配置 ===================="
if uci -q get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
  echo "  清理前 server: $(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null | tr '\n' ' ')"
  uci -q delete dhcp.@dnsmasq[0].server
  uci -q delete dhcp.@dnsmasq[0].strictorder
  uci -q delete dhcp.@dnsmasq[0].noresolv
  uci -q delete dhcp.@dnsmasq[0].allservers
  uci -q delete dhcp.@dnsmasq[0].resolvfile
  uci -q set dhcp.@dnsmasq[0].cachesize='10000'
  uci -q set dhcp.@dnsmasq[0].dnsforwardmax='1000'
  uci -q set dhcp.@dnsmasq[0].rebind_protection='0'
  uci -q commit dhcp
  /etc/init.d/dnsmasq restart >/dev/null 2>&1
  echo "  ✅ dnsmasq 已无自定义上游（只留 DHCP/缓存；包本身保留）"
  echo "     未开 PassWall 时会回落到 WAN 下发的 DNS，不会断网"
else
  echo "  ⚠ dhcp.@dnsmasq[0] 不存在，跳过"
fi

echo
echo "==================== 2) PassWall 接管 DNS ===================="
if [ -x /etc/init.d/passwall ]; then
  if [ ! -f /etc/config/passwall ] && [ -f /usr/share/passwall/0_default_config ]; then
    mkdir -p /etc/config
    cp /usr/share/passwall/0_default_config /etc/config/passwall
    echo "  已从 0_default_config 复制完整默认配置"
  fi
  if uci -q get passwall.@global[0] >/dev/null 2>&1; then
    if [ -x /usr/bin/chinadns-ng ] || command -v chinadns-ng >/dev/null 2>&1; then
      echo "  ✅ chinadns-ng 二进制在位，可以安全接管 53"
    else
      echo "  ❌ 没找到 chinadns-ng！这个固件是旧版（PassWall 的 LUCI_DEPENDS 原本就带它，"
      echo "     但旧 config 可能没拉进来）。**先别勾启用 PassWall**，否则 53 被劫持到"
      echo "     无人监听的端口会断网。重编固件或 apk add chinadns-ng 后再跑本脚本。"
    fi
    uci -q set passwall.@global[0].dns_shunt='chinadns-ng'
    uci -q set passwall.@global[0].dns_redirect='1'
    uci -q set passwall.@global[0].direct_dns='223.5.5.5'
    uci -q set passwall.@global[0].direct_dns_mode='udp'
    uci -q set passwall.@global[0].use_default_dns='direct'
    uci -q set passwall.@global[0].filter_proxy_ipv6='0'
    if uci -q get passwall.@global_forwarding[0] >/dev/null 2>&1; then
      uci -q set passwall.@global_forwarding[0].tcp_no_redir_ports='disable'
      uci -q set passwall.@global_forwarding[0].udp_no_redir_ports='disable'
    fi
    # helper_dnsmasq.lua 启停时会把旧 server 列表合并回写
    uci -q delete passwall.@global[0].dnsmasq_servers 2>/dev/null
    uci -q delete passwall.@global[0].dnsmasq_dns_redirect 2>/dev/null
    uci -q commit passwall
    echo "  ✅ PassWall: dns_shunt=chinadns-ng / dns_redirect=1 / direct_dns=223.5.5.5"
    echo "     链路: LAN → PassWall dnsmasq(53) → chinadns-ng → 国内直连/国外远端"
  else
    echo "  ⚠ passwall.@global[0] 不存在，跳过（不写残缺配置）"
  fi
else
  echo "  ℹ 未安装 PassWall，跳过"
fi

echo
echo "==================== 3) DDNS 只留花生壳 ===================="
if [ -f /usr/share/ddns/default/oray.com.json ]; then
  echo "  ✅ oray.com provider 在位"
  # 收敛服务商列表：只留花生壳（等价新固件首启的 99-zz-ddns-only-oray）
  CUT=0
  for f in /usr/share/ddns/default/*.json; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      oray.com.json) ;;
      *) rm -f "$f" && CUT=$((CUT + 1)) ;;
    esac
  done
  echo "  已删除 $CUT 个非花生壳 provider，LuCI 服务商下拉只剩 oray.com"
  if [ -f /etc/config/ddns ]; then
    SCUT=0
    for s in $(uci -q show ddns 2>/dev/null | sed -n 's/^ddns\.\([^.=]*\)=service$/\1/p'); do
      if [ "$s" != "oray" ]; then uci -q delete "ddns.$s" && SCUT=$((SCUT + 1)); fi
    done
    [ "$SCUT" -gt 0 ] && { uci -q commit ddns; echo "  已删除 $SCUT 条非 oray 的 service 段"; }
    if uci -q get ddns.oray >/dev/null 2>&1; then
      echo "  oray 段存在，enabled=$(uci -q get ddns.oray.enabled 2>/dev/null || echo '0')"
      echo "  填好账号后启用："
      echo "    uci set ddns.oray.username='你的Oray账号'"
      echo "    uci set ddns.oray.password='花生壳管理密码'"
      echo "    uci set ddns.oray.lookup_host='xxx.oray.net'"
      echo "    uci set ddns.oray.domain='xxx.oray.net'"
      echo "    uci set ddns.oray.enabled='1'; uci commit ddns"
      echo "    /etc/init.d/ddns restart"
    else
      echo "  ⚠ /etc/config/ddns 里没有 oray 段，LuCI「服务 → 动态 DNS」添加，"
      echo "    服务商必须选 oray.com（不是 oray）"
    fi
  fi
else
  echo "  ⚠ 没有 oray.com.json —— 缺 ddns-scripts-services，重编或 apk add 后才有花生壳"
fi
# Lucky：本版已整个移除，旧固件上提醒别再用它配 DDNS
if [ -x /etc/init.d/lucky ] || [ -x /usr/bin/lucky ]; then
  echo "  ⚠ 检测到旧固件仍装着 Lucky（另一个 DDNS 客户端）。本版已整组移除。"
  echo "    别再在 Lucky 里配 DDNS，统一用上面的 oray；否则两边更新同一域名会触发"
  echo "    花生壳 abuse 频率限制。Lucky 的 socat 反代若还要用，可单独保留但不配 DDNS。"
  echo "    彻底停用：/etc/init.d/lucky stop && /etc/init.d/lucky disable"
else
  echo "  ℹ Lucky 未安装（本版已移除，符合「只留花生壳」）"
fi

echo
echo "==================== 4) 服务自检 ===================="
echo "  dnsmasq server : $(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null | tr '\n' ' ' || echo '(已清空)')"
echo "  strictorder    : $(uci -q get dhcp.@dnsmasq[0].strictorder 2>/dev/null || echo '(已删除)')"
echo "  noresolv       : $(uci -q get dhcp.@dnsmasq[0].noresolv 2>/dev/null || echo '(已删除)')"
if [ -f /etc/config/passwall ]; then
  echo "  PassWall 分流  : $(uci -q get passwall.@global[0].dns_shunt 2>/dev/null || echo '(未设)')"
  echo "  PassWall 劫持  : $(uci -q get passwall.@global[0].dns_redirect 2>/dev/null || echo '(未设)')"
  echo "  PassWall 启用  : $(uci -q get passwall.@global[0].enabled 2>/dev/null || echo '0')"
fi
echo "  chinadns-ng    : $(command -v chinadns-ng 2>/dev/null || echo '未找到')"
echo "  SmartDNS 进程  : $(pidof smartdns 2>/dev/null || echo '无（本版已移除）')"
echo "  rtp2httpd      : $(command -v rtp2httpd 2>/dev/null || echo '未找到（旧固件）')"
echo "  Lucky          : $(command -v lucky 2>/dev/null || echo '未安装（本版已移除）')"
echo "  DDNS providers : $(ls -1 /usr/share/ddns/default/*.json 2>/dev/null | wc -l) 个（期望仅 oray.com.json）"
echo "  Homebox        : $(command -v homebox 2>/dev/null || echo '未安装（去重已移除）')"
echo "  omcproxy       : $(command -v omcproxy 2>/dev/null || echo '未找到（旧固件）')"
echo "  igmpproxy      : $(command -v igmpproxy 2>/dev/null || echo '未找到（旧固件／本版已恢复）')"
echo "  IGMP Snooping  : uci=$(uci -q get network.@device[0].igmp_snooping 2>/dev/null || uci -q get network.lan.igmp_snooping 2>/dev/null || echo '未设')"
echo "                   sysfs=$(cat /sys/class/net/br-lan/bridge/multicast_snooping 2>/dev/null || echo 'br-lan 未建（首启正常）')"
echo "  dnsmasq 进程   : $(pidof dnsmasq 2>/dev/null || echo '无')"
echo "  → 期望: server 为空、PassWall 分流=chinadns-ng、劫持=1、chinadns-ng 有路径。"

echo
echo "==================== 5) 组播双代理 / IGMP Snooping 复查 ===================="
echo "  本版口径：组播=omcproxy + igmpproxy 两个都保留；测速=FastNet；DDNS=花生壳；代理=PassWall"

# 组播双代理
HAS_OMC=0; HAS_IGMP=0
command -v omcproxy >/dev/null 2>&1 && HAS_OMC=1
command -v igmpproxy >/dev/null 2>&1 && HAS_IGMP=1
if [ "$HAS_OMC" = "1" ] && [ "$HAS_IGMP" = "1" ]; then
  echo "  ✅ 两个组播代理都在（omcproxy / igmpproxy）"
  echo "  ⚠ 别同时在同一上行接口启用：IPv4 IPTV 用 igmpproxy，ONU 菜单组播路径用 omcproxy"
else
  echo "  ⚠ 组播代理不全：omcproxy=$HAS_OMC igmpproxy=$HAS_IGMP（旧固件？本版两个都编入）"
  echo "    需重编本版固件；临时用 apk add omcproxy igmpproxy luci-app-igmpproxy"
fi

# IGMP Snooping（用户要求「igmp snooping 也要」）
SNOOP_UCI="$(uci -q get network.@device[0].igmp_snooping 2>/dev/null || uci -q get network.lan.igmp_snooping 2>/dev/null || echo '')"
echo "  IGMP Snooping  : UCI=${SNOOP_UCI:-未设}"
if [ "$SNOOP_UCI" = "1" ]; then
  echo "  ✅ UCI 已开启（首启脚本 99-zz-igmp-snooping 写的，network reload 后生效）"
else
  echo "  ⚠ 旧固件没开，现机补开（整段复制执行）："
  echo '    for s in $(uci -q show network | sed -n "s/^network\.\([^.=]*\)=device$/\1/p"); do'
  echo '      [ "$(uci -q get network.$s.type)" = "bridge" ] && uci -q set network.$s.igmp_snooping=1'
  echo '    done; uci commit network; /etc/init.d/network reload'
  echo "    或直接刷本版固件（出厂自动开）"
fi
SYSFS="$(cat /sys/class/net/br-lan/bridge/multicast_snooping 2>/dev/null || echo '')"
if [ -n "$SYSFS" ]; then
  echo "  sysfs multicast_snooping = $SYSFS（期望 1）"
  [ "$SYSFS" = "1" ] || echo 1 > /sys/class/net/br-lan/bridge/multicast_snooping 2>/dev/null
else
  echo "  ℹ sysfs 暂不可读（br-lan 未建 / 内核未编 CONFIG_BRIDGE_IGMP_SNOOPING），"
  echo "    首启脚本会打 logread -e igmp-snoop 提示，不是错误"
fi

# 旧固件上 Homebox 仍装着 → 只提示，不擅自删
if [ -x /usr/bin/homebox ]; then
  echo "  ℹ 检测到 Homebox（本版已移除的重复测速插件，:3300）。"
  echo "    测速统一用 FastNet；如不需要可 /etc/init.d/homebox stop && disable"
fi

if command -v rtp2httpd >/dev/null 2>&1; then
  echo "  ✅ rtp2httpd 已编入（v3.17.2），LuCI「服务 → rtp2httpd」配置组播源"
else
  echo "  ℹ 旧固件没有 rtp2httpd，需重编本版固件"
fi

echo
echo "==================== 6) PassWall 首次使用 ===================="
echo "  首页 TCP / UDP / DNS / HAPROXY「未运行」= 尚未配置节点，正常："
echo "    ① 节点订阅 → 添加订阅链接 → 更新"
echo "    ② 节点列表 → 选一个节点"
echo "    ③ 基本设置 → 勾选「启用」→ 保存并应用"
echo "  固件已带 xray-core / sing-box 内核，HAPROXY 默认 N/A。"

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
echo
echo "===== 完成，回 LuCI 点右上角「刷新」 ====="
exit 0
