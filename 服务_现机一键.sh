#!/bin/sh
# 服务_现机一键.sh —— 已刷固件，SSH 整段粘贴
# 修「上网时间控制Plus 未运行」+ 清掉抢 53 的旧规则 + PassWall 启动检查
# 2026-11-25；不依赖仓库文件，全部内联。
echo "==================== 1) 诊断 ===================="
echo -n "  iptables 命令    : "; command -v iptables || echo "❌ 不存在 → 这就是 miaplus 永远「未运行」的原因"
echo -n "  nft 命令         : "; command -v nft || echo "无"
echo -n "  旧 miaplus 配置  : "; cat /etc/config/miaplus 2>/dev/null | tr '\n' ' ' || echo "（无）"; echo
echo -n "  fw3 include      : "; uci -q get firewall.miaplus 2>/dev/null || echo "无"
echo -n "  miaplus enable   : "; uci -q get miaplus.@basic[0].enable 2>/dev/null || echo "无"
echo -n "  PassWall enabled : "; uci -q get passwall.@global[0].enabled 2>/dev/null || echo "无"
echo -n "  PassWall 节点    : "; uci -q get passwall.@global[0].node 2>/dev/null || echo "❌ 没选节点（PassWall 不会启动代理）"
echo -n "  节点段数量       : "; uci show passwall 2>/dev/null | grep -c '=nodes' || echo 0
echo

echo "==================== 2) 清掉旧 fw3 include / 53 劫持 ===================="
if uci -q get firewall.miaplus >/dev/null 2>&1; then
  uci -q delete firewall.miaplus; uci -q commit firewall
  echo "  ✅ 已删除 firewall.miaplus（fw4 会执行它 → 抢 53）"
else
  echo "  firewall.miaplus 不存在，无需删"
fi
# 若系统侥幸有 iptables-nft 兼容层，清掉 MIAPLUS 链与 53 REDIRECT
if command -v iptables >/dev/null 2>&1; then
  for t in filter nat; do
    iptables -t "$t" -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control" 2>/dev/null
    iptables -t "$t" -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control" 2>/dev/null
    iptables -t "$t" -D INPUT -p udp --dport 53 -j MIAPLUS 2>/dev/null
    iptables -t "$t" -D INPUT -p tcp --dport 53 -j MIAPLUS 2>/dev/null
    iptables -t "$t" -F MIAPLUS 2>/dev/null
    iptables -t "$t" -X MIAPLUS 2>/dev/null
  done
  echo "  ✅ 已清 MIAPLUS 链与 53 REDIRECT"
fi
echo

echo "==================== 3) 装 nftables 版 miaplus 后端 ===================="
cat > /etc/init.d/miaplus <<'EOF'
#!/bin/sh /etc/rc.common
START=30
STOP=10
USE_PROCD=1
APPLY=/usr/sbin/miaplus-apply
start_service() {
  [ -x "$APPLY" ] || return 0
  "$APPLY"
  logger -t miaplus "服务已启动：table inet miaplus（forward 按 MAC 管控，不碰 53）"
}
stop_service() {
  command -v nft >/dev/null 2>&1 && nft delete table inet miaplus 2>/dev/null
  logger -t miaplus "服务已停止"
}
service_triggers() { procd_add_reload_trigger miaplus; }
reload_service() { [ -x "$APPLY" ] && "$APPLY"; }
EOF

cat > /usr/sbin/miaplus-apply <<'EOF'
#!/bin/sh
log() { logger -t miaplus "$@"; }
CFG=/etc/config/miaplus
[ -f "$CFG" ] || exit 0
command -v nft >/dev/null 2>&1 || exit 0
# ⚠ busybox ash / dash 的 $(( )) **不支持 bash 的 10# 前缀**，
#   date +%H 返回 "08" 直接算会被当八进制报错。纯 POSIX 去前导零。
strip0() { _v="$1"; while [ "${_v#0}" != "$_v" ]; do _v="${_v#0}"; done; [ -n "$_v" ] || _v=0; echo "$_v"; }

DOW="$(date +%u)"; NOW="$(date +%H:%M)"
NOW_MIN=$(( $(strip0 "${NOW%%:*}") * 60 + $(strip0 "${NOW##*:}") ))
u() { uci -q get "$1" 2>/dev/null; }
in_window() {
  _on="$1"; _off="$2"
  case "$_on" in *:*) ;; *) return 1 ;; esac
  case "$_off" in *:*) ;; *) return 1 ;; esac
  _a=$(( $(strip0 "${_on%%:*}") * 60 + $(strip0 "${_on##*:}") ))
  _b=$(( $(strip0 "${_off%%:*}") * 60 + $(strip0 "${_off##*:}") ))
  if [ "$_a" -le "$_b" ]; then [ "$NOW_MIN" -ge "$_a" ] && [ "$NOW_MIN" -le "$_b" ]
  else [ "$NOW_MIN" -ge "$_a" ] || [ "$NOW_MIN" -le "$_b" ]; fi
}
template_allows() {
  _t="$1"; _i=0
  while [ "$_i" -lt 100 ]; do
    _en="$(u "miaplus.@${_t}[${_i}].enable")"
    [ -z "$_en" ] && break
    if [ "$_en" = "1" ]; then
      _z="$(u "miaplus.@${_t}[${_i}].z${DOW}")"
      if [ "$_z" != "0" ] && in_window "$(u "miaplus.@${_t}[${_i}].timeon")" "$(u "miaplus.@${_t}[${_i}].timeoff")"; then return 0; fi
    fi
    _i=$((_i+1))
  done
  return 1
}
EN="$(u miaplus.@basic[0].enable)"; [ -z "$EN" ] && EN=0
F=/tmp/miaplus.nft
{
  echo 'table inet miaplus'; echo 'flush table inet miaplus'
  echo 'table inet miaplus {'; echo '    chain forward {'
  echo '        type filter hook forward priority 0; policy accept;'
  if [ "$EN" = "1" ]; then
    _i=0; BLOCKED=0
    while [ "$_i" -lt 100 ]; do
      _en="$(u "miaplus.@macbind[${_i}].enable")"
      [ -z "$_en" ] && break
      _mac="$(u "miaplus.@macbind[${_i}].macaddr")"
      _tpl="$(u "miaplus.@macbind[${_i}].template")"
      if [ "$_en" = "1" ] && [ -n "$_mac" ] && [ -n "$_tpl" ]; then
        _mac="$(printf '%s' "$_mac" | tr 'A-F-' 'a-f:')"
        if ! template_allows "$_tpl"; then
          echo "        ether saddr $_mac drop comment \"miaplus: outside schedule\""
          BLOCKED=$((BLOCKED+1))
        fi
      fi
      _i=$((_i+1))
    done
    LOGMSG="enable=1  ${NOW} 周${DOW}  阻断 ${BLOCKED} 个 MAC"
  else
    LOGMSG="enable=0  未启用，chain 为空"
  fi
  echo '    }'; echo '}'
} > "$F"
log "${LOGMSG}"
nft -c -f "$F" >/dev/null 2>&1 || { log "nft 校验失败，保留旧规则"; exit 0; }
nft -f "$F" 2>/dev/null || log "nft 加载失败"
exit 0
EOF

# 覆盖 LuCI controller 的状态判定（原来靠 iptables -L）
cat > /usr/lib/lua/luci/controller/miaplus.lua <<'EOF'
module("luci.controller.miaplus",package.seeall)
function index()
	if not nixio.fs.access("/etc/config/miaplus") then return end
	entry({"admin", "services", "miaplus"}, cbi("base"), _("Internet Access Schedule Control Plus"), 30).dependent = true
	entry({"admin", "services", "miaplus", "status"}, call("act_status")).leaf = true
	entry({"admin", "services", "miaplus", "base"}, cbi("base"), _("Base Setting"), 40).leaf = true
	entry({"admin", "services", "miaplus", "advanced"}, cbi("advanced"), _("Advance Setting"), 50).leaf = true
	entry({"admin", "services", "miaplus", "template"}, cbi("template"), nil).leaf = true
end
function act_status()
	local e = {}
	e.running = luci.sys.call("nft list table inet miaplus >/dev/null 2>&1") == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
EOF

chmod +x /etc/init.d/miaplus /usr/sbin/miaplus-apply
[ -f /etc/miaplus.include ] && printf '#!/bin/sh\nexit 0\n' > /etc/miaplus.include && chmod +x /etc/miaplus.include
sh -n /etc/init.d/miaplus && sh -n /usr/sbin/miaplus-apply && echo "  ✅ 两个脚本语法通过"

# 出厂配置：enable=1（空规则＝运行状态、不限制任何客户端）
if [ ! -f /etc/config/miaplus ]; then
  cat > /etc/config/miaplus <<'EOF'
config basic
	option enable '1'
	option strict '0'
	option ipv6enable '0'

config templates
	option enable '1'
	option title 'default'
EOF
else
  [ "$(uci -q get miaplus.@basic[0].enable)" != "1" ] && uci -q set miaplus.@basic[0].enable='1' && uci -q commit miaplus
fi

# cron 每分钟重算（nftables 无内建时间段匹配）
if command -v crontab >/dev/null 2>&1; then
  T="$(mktemp)"; crontab -l 2>/dev/null | grep -vF '/usr/sbin/miaplus-apply' > "$T" || true
  echo '* * * * * /usr/sbin/miaplus-apply >/dev/null 2>&1' >> "$T"
  crontab "$T" 2>/dev/null; rm -f "$T"; echo "  ✅ 已注册 cron"
fi

/etc/init.d/miaplus enable 2>/dev/null
/etc/init.d/miaplus restart 2>/dev/null
sleep 1
echo -n "  table inet miaplus : "; nft list table inet miaplus >/dev/null 2>&1 && echo "✅ 存在（LuCI 应显示 RUNNING）" || echo "❌ 未建立"
echo

echo "==================== 4) PassWall 检查 ===================="
echo "  enabled = $(uci -q get passwall.@global[0].enabled 2>/dev/null || echo 0)   node = $(uci -q get passwall.@global[0].node 2>/dev/null || echo 未设置)"
echo "  节点段  = $(uci show passwall 2>/dev/null | grep -c '=nodes') 个"
echo "  ⚠ 没节点就不会启动代理：服务 → PassWall → 节点订阅(填订阅URL并更新)"
echo "       → 节点列表(选一个) → 基本设置(勾「启用」) → 等 10~30 秒刷新"
echo "  首页「GitHub 连接失败」是浏览器直连测试，不是 PassWall 状态，不用管"
echo "  详细三步见仓库 PassWall_启用引导.md"
echo "  日志：logread -e PSW | tail -40"
echo

# 刷 LuCI 索引缓存，状态页立刻用新 controller
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >/dev/null 2>&1 || true
echo "  ✅ LuCI 索引缓存已刷新，Ctrl+F5 刷新页面查看"

echo
echo "==================== 5) v13 服务自启兜底 ===================="
# cron：miaplus 每分钟重算 + taskplan 定时都靠它
CRONTAB=/etc/crontabs/root
LINE='* * * * * /usr/sbin/miaplus-apply >/dev/null 2>&1'
if [ -x /etc/init.d/cron ]; then
  mkdir -p /etc/crontabs
  [ -f "$CRONTAB" ] || : > "$CRONTAB"
  T="$(mktemp)"; grep -vF '/usr/sbin/miaplus-apply' "$CRONTAB" 2>/dev/null > "$T" || true
  echo "$LINE" >> "$T"; cat "$T" > "$CRONTAB"; rm -f "$T"
  chmod 600 "$CRONTAB" 2>/dev/null || true
  /etc/init.d/cron enable 2>/dev/null || true
  /etc/init.d/cron restart 2>/dev/null || true
  echo -n "  crond        : "; pidof crond >/dev/null 2>&1 && echo "✅ 运行中" || echo "⚠ 未起（查 logread）"
else
  echo "  ⚠ /etc/init.d/cron 不存在"
fi
# sysntpd：NTP 服务端
if [ -x /etc/init.d/sysntpd ]; then
  uci -q set system.ntp.enable_server='1'; uci -q commit system
  /etc/init.d/sysntpd enable 2>/dev/null || true
  /etc/init.d/sysntpd restart 2>/dev/null || true
  echo -n "  ntpd :123   : "; pidof ntpd >/dev/null 2>&1 && echo "✅ 运行中" || echo "⚠ 未起"
fi
# rtp2httpd：上游默认 disabled=1
if [ -x /etc/init.d/rtp2httpd ]; then
  if [ -f /etc/config/rtp2httpd ]; then
    uci -q set rtp2httpd.@rtp2httpd[0].disabled='0'
    uci -q del_list rtp2httpd.@rtp2httpd[0].listen='5140' 2>/dev/null || true
    uci -q add_list rtp2httpd.@rtp2httpd[0].listen='5140'
    uci -q commit rtp2httpd
  fi
  /etc/init.d/rtp2httpd enable 2>/dev/null || true
  /etc/init.d/rtp2httpd restart 2>/dev/null || true
  echo -n "  rtp2httpd    : "; pidof rtp2httpd >/dev/null 2>&1 && echo "✅ 运行中 (:5140)" || echo "⚠ 未起（查 logread -e rtp2httpd）"
else
  echo "  rtp2httpd    : 未安装，跳过"
fi
# 统一 reload：让组播放行 include 生效
command -v fw4 >/dev/null 2>&1 && fw4 reload >/dev/null 2>&1 && echo "  ✅ fw4 reload：rogue_dhcp / multicast_allow 两条 include 已加载"
echo
echo "  仍需手动配置：PassWall（订阅→选节点→勾启用）、花生壳 DDNS（Oray 账号）、"
echo "                USB 打印（插打印机后在 LuCI 启用）、igmpproxy/omcproxy（组播上游二选一）"
