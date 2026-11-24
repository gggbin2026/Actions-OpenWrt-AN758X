#!/bin/sh
# DNS_现机清理.sh —— 已刷机、不想重编时，SSH 进去整段粘贴即可
# 作用：清掉旧固件带过来的 SmartDNS 菜单/配置/缓存；确认系统 DNS 只剩
#       dnsmasq（DHCP+缓存，不配上游），PassWall 独占解析。
echo "=== 1) 清残留 ==="
N=0
for F in /etc/config/smartdns /etc/init.d/smartdns /etc/smartdns/smartdns.conf \
         /usr/bin/smartdns /usr/sbin/smartdns /etc/rc.d/*smartdns*; do
  [ -e "$F" ] && { rm -f -- "$F" && echo "  删 $F" && N=$((N+1)); }
done
for D in /usr/lib/lua/luci/controller /usr/lib/lua/luci/model /usr/lib/lua/luci/view \
         /usr/share/luci/menu.d /usr/share/luci/modals; do
  [ -d "$D" ] && find "$D" -maxdepth 4 -iname '*smartdns*' -type f \
      -exec sh -c 'echo "  删 $1"; rm -f -- "$1"' _ {} \;
done
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null
[ -d /tmp/luci-modulecache ] && rm -rf /tmp/luci-modulecache/* 2>/dev/null
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
echo "  共清 $N 个配置/服务残留；重开浏览器（Ctrl+F5）再看菜单"

echo
echo "=== 2) 验证（应该看到的） ==="
echo -n "  smartdns 进程 : "; pidof smartdns 2>/dev/null || echo "无 ✅"
echo -n "  dnsmasq 进程  : "; pidof dnsmasq 2>/dev/null || echo "无 ⚠（应有一个，负责 DHCP）"
echo -n "  dnsmasq 上游  : "; uci -q get dhcp.@dnsmasq[0].server || echo "无（未配上游）✅"
echo -n "  noresolv      : "; uci -q get dhcp.@dnsmasq[0].noresolv || echo "无 ✅"
echo -n "  PassWall 分流 : "; uci -q get passwall.@global[0].dns_shunt || echo "未启用代理"
echo -n "  chinadns-ng   : "; command -v chinadns-ng || echo "未找到 ⚠"
echo
echo "  说明：「网络 → DHCP/DNS」页面 = dnsmasq，是 DHCP/缓存基础设施，"
echo "        不是 DNS 插件，不能删；删了 LAN 拿不到 IP、PassWall 起不来。"
echo "        PassWall → DNS 设置里若还能选 SmartDNS，那是前端写死的下拉项，别选"
echo "        （本固件没编 smartdns，选了会 53 断网）。"
