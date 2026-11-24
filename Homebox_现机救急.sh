#!/bin/sh
# Homebox_现机救急.sh —— 已刷旧固件、暂不重编时 SSH 整段粘贴
# 作用：补齐 config/init.d、设为自启、立刻拉起，并打印自检结果。
echo "=== 1) 确认二进制与启动方式 ==="
if [ ! -x /usr/bin/homebox ]; then
  echo "  ❌ /usr/bin/homebox 不存在：这个固件没编入 Homebox，只能重编"
  exit 1
fi
if /usr/bin/homebox --help 2>&1 | grep -q 'serve'; then
  echo "  ✅ v1.0.1+ Rust 版：启动必须带 serve 子命令"
  MODE=serve
else
  echo "  ✅ 老版：裸跑即可"
  MODE=plain
fi

echo
echo "=== 2) 补配置（已存在则不覆盖）==="
if [ ! -f /etc/config/homebox ]; then
  cat > /etc/config/homebox <<'EOF'
config homebox 'homebox'
	option enabled '1'
	option port '3300'
	option logger '0'
EOF
else
  uci set homebox.@homebox[0].enabled='1' 2>/dev/null
  uci commit homebox 2>/dev/null
fi
echo "  enabled = $(uci -q get homebox.@homebox[0].enabled)"
echo "  port    = $(uci -q get homebox.@homebox[0].port)"

echo
echo "=== 3) 写/修 init.d 并拉起 ==="
cat > /etc/init.d/homebox <<EOF
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1
BIN="/usr/bin/homebox"
start_service() {
	[ -x "\$BIN" ] || return 0
	config_load homebox
	local enabled port
	config_get enabled homebox enabled '0'
	config_get port homebox port '3300'
	[ "\$enabled" = "1" ] || return 0
	procd_open_instance
	if [ "$MODE" = serve ]; then
		procd_set_param command "\$BIN" serve --host 0.0.0.0 --port "\$port"
	else
		procd_set_param command "\$BIN" --host 0.0.0.0 --port "\$port"
	fi
	procd_set_param respawn
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance
}
service_triggers() { procd_add_reload_trigger homebox; }
EOF
chmod +x /etc/init.d/homebox
/etc/init.d/homebox enable
/etc/init.d/homebox restart

echo
echo "=== 4) 自检 ==="
echo -n "  pidof homebox : "; pidof homebox 2>/dev/null || echo "无 ⚠（看下面 logread）"
echo -n "  :3300 监听   : "; netstat -lnt 2>/dev/null | grep ':3300' || echo "未监听"
echo
echo "  仍不运行就看：logread | tail -30"
echo "  浏览器访问：http://192.168.1.1:3300"
echo "  LuCI 菜单  ：服务 → Homebox（若没出现，重启 rpcd 或清 /tmp/luci-indexcache*）"
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null
