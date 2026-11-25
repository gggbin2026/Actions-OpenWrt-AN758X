#!/bin/sh
# 组播_现机一键.sh —— 已刷固件不想重编时，SSH 整段粘贴
# 作用：所有桥开 IGMP Snooping + Querier、每个网口配置组播参数、
#       放行 IGMP/组播、按需启用 igmpproxy 上游订阅。
# 2026-11-25 版；不依赖仓库里的新文件，全部内联。
ROOT="/sys/class/net"
MROUTER="${ALL_PORTS_MROUTER:-1}"     # 想每口都收全量组播就 export ALL_PORTS_MROUTER=2

setw() { [ -w "$1" ] || return 0; [ "$(cat "$1" 2>/dev/null)" = "$2" ] && return 0; echo "$2" > "$1" 2>/dev/null || true; }

echo "==================== 1) 逐桥 / 逐端口组播参数 ===================="
NB=0; NP=0
for b in "$ROOT"/*/bridge; do
  [ -d "$b" ] || continue
  br="$(basename "$(dirname "$b")")"; NB=$((NB+1))
  setw "$b/multicast_snooping" 1
  setw "$b/multicast_querier"  1
  setw "$b/multicast_query_interval" 6000
  setw "$b/multicast_router" 2
  echo -n "  桥 $br : snooping=$(cat "$b/multicast_snooping" 2>/dev/null) "
  echo    "querier=$(cat "$b/multicast_querier" 2>/dev/null) self_mrouter=$(cat "$b/multicast_router" 2>/dev/null || echo n/a)"
  for p in "$ROOT/$br/brif"/*; do
    [ -d "$p" ] || continue
    pn="$(basename "$p")"; NP=$((NP+1))
    setw "$p/multicast_router" "$MROUTER"
    setw "$p/multicast_fast_leave" 1
    case "$pn" in
      phy*-ap*|wlan*|ra[0-9]*|rai[0-9]*|wl*) setw "$p/multicast_to_unicast" 1 ;;
    esac
    echo "    端口 $pn : mrouter=$(cat "$p/multicast_router" 2>/dev/null) fast_leave=$(cat "$p/multicast_fast_leave" 2>/dev/null || echo n/a)"
  done
done
echo "  合计：$NB 个桥 / $NP 个端口（MROUTER=$MROUTER）"
echo

echo "==================== 2) 防火墙放行 IGMP / 组播 ===================="
if command -v nft >/dev/null 2>&1; then
  nft -f - <<'EOF' 2>/dev/null && echo "  ✅ 已加载 inet multicast_allow" || echo "  ⚠ nft 加载失败（不阻断，policy 默认 accept）"
table inet multicast_allow
flush table inet multicast_allow
table inet multicast_allow {
    chain input {
        type filter hook input priority -10; policy accept;
        ip protocol 2 accept
        ip daddr 224.0.0.0/4 accept
    }
}
EOF
  nft list table inet multicast_allow 2>/dev/null | head -12
else
  echo "  本机无 nft 命令，跳过"
fi
echo

echo "==================== 3) 组播上游（igmpproxy / omcproxy 二选一）===================="
if [ ! -f /etc/config/igmpproxy ]; then
  cat > /etc/config/igmpproxy <<'EOF'
config igmpproxy
	option quickleave '1'

config phyint
	option network 'wan'
	option zone 'wan'
	option direction 'upstream'
	list altnet '0.0.0.0/0'

config phyint
	option network 'lan'
	option zone 'lan'
	option direction 'downstream'
EOF
  echo "  已生成 /etc/config/igmpproxy 模板"
else
  echo "  /etc/config/igmpproxy 已存在，保留不覆盖"
fi

OMC_ON=0
[ -x /etc/init.d/omcproxy ] && /etc/init.d/omcproxy enabled >/dev/null 2>&1 && OMC_ON=1
if [ "$OMC_ON" = "1" ]; then
  echo "  omcproxy 已启用 → 不启用 igmpproxy（两个代理同时在上行会抢 IGMP 加入）"
  echo "  如确认只用 igmpproxy：/etc/init.d/omcproxy disable; /etc/init.d/igmpproxy enable; /etc/init.d/igmpproxy restart"
else
  if [ -x /etc/init.d/igmpproxy ]; then
    /etc/init.d/igmpproxy enable 2>/dev/null || true
    /etc/init.d/igmpproxy restart 2>/dev/null || true
    echo -n "  igmpproxy: "; /etc/init.d/igmpproxy status 2>/dev/null || pidof igmpproxy || echo "未运行"
  else
    echo "  未找到 igmpproxy init.d（包未编入？）"
  fi
fi
echo

echo "==================== 4) 核对 ===================="
echo "  bridge mdb    : bridge -d mdb show 2>/dev/null || bridge mdb show"
echo "  IGMP 组成员   : cat /proc/net/igmp"
echo "  组播代理日志  : logread -e igmpproxy; logread -e omcproxy"
echo "  放行表        : nft list table inet multicast_allow"
echo "  组播转发      : cat /proc/sys/net/ipv4/conf/all/mc_forwarding"
echo
echo "  ⚠ 同时启用 igmpproxy 与 omcproxy 在同一上行 = 重复加入/争抢，务必二选一。"
echo "  ⚠ MROUTER=2 会让组播泛洪到每个口（含 WiFi），高码率 IPTV 慎用；"
echo "    需要时：export ALL_PORTS_MROUTER=2 后重跑本脚本。"
