#!/bin/sh
# Homebox_现机救急.sh —— 已刷固件、不想重编时 SSH 整段粘贴
# 2026-11-25 版：定位 + 修 config(匿名 section) + 修 init.d(裸跑) + 拉起 + 自检
# 用法：ssh root@192.168.1.1 后整段粘贴，或 sh -c "$(cat 此文件)"
echo "==================== 1) 诊断（先看清楚原来卡在哪）===================="
echo -n "  二进制        : "; ls -l /usr/bin/homebox 2>/dev/null || echo "❌ 不存在（说明包没编进固件，只能重编）"
echo -n "  当前 pidof    : "; pidof homebox 2>/dev/null || echo "无 ← 这就是 LuCI 红字的原因"
echo -n "  init.d        : "; ls -l /etc/init.d/homebox 2>/dev/null || echo "❌ 不存在"
echo -n "  rc.d 链接     : "; ls /etc/rc.d/*homebox* 2>/dev/null || echo "无（服务没设自启）"
echo    "  当前 /etc/config/homebox :"; cat /etc/config/homebox 2>/dev/null || echo "  （无）"
echo    "  最近日志      :"; logread 2>/dev/null | grep -i homebox | tail -5 || true
echo

echo "==================== 2) 修配置：匿名 section + enabled=1 ===================="
cat > /etc/config/homebox <<'EOF'
config homebox
	option enabled '1'
	option port '3300'
	option logger '0'
EOF
echo "  已写入。uci 读取校验:"
echo -n "    homebox.@homebox[0].enabled = "; uci -q get homebox.@homebox[0].enabled
echo

echo "==================== 3) 修 init.d：按 type 读取 + 裸跑启动 ===================="
cat > /etc/init.d/homebox <<'EOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1
BIN="/usr/bin/homebox"

start_service() {
	[ -x "$BIN" ] || return 0
	local enabled port
	enabled="$(uci -q get homebox.@homebox[0].enabled 2>/dev/null)"
	port="$(uci -q get homebox.@homebox[0].port 2>/dev/null)"
	[ -z "$enabled" ] && enabled='1'
	[ -z "$port" ] && port='3300'
	[ "$enabled" = "1" ] || return 0
	procd_open_instance
	procd_set_param command "$BIN"
	procd_set_param respawn
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance
	logger -t homebox "已启动（默认 0.0.0.0:${port}）"
}

service_triggers() {
	procd_add_reload_trigger homebox
}
EOF
chmod +x /etc/init.d/homebox
sh -n /etc/init.d/homebox && echo "  ✅ init.d 语法通过" || echo "  ❌ init.d 语法有误"
echo

echo "==================== 4) 设为自启并立刻拉起 ===================="
/etc/init.d/homebox enable
/etc/init.d/homebox restart
sleep 2
echo

echo "==================== 5) 自检 ===================="
echo -n "  pidof homebox : "; pidof homebox 2>/dev/null || echo "❌ 仍无进程"
echo -n "  :3300 监听   : "; netstat -lnt 2>/dev/null | grep ':3300' || echo "未监听"
echo -n "  自启链接     : "; ls /etc/rc.d/*homebox* 2>/dev/null || echo "无"
echo -n "  /ping 探活   : "; wget -qO- --timeout=3 http://127.0.0.1:3300/ping 2>/dev/null || echo "（无 wget 或服务未就绪）"
echo
echo "  LuCI 刷新：服务 → Homebox 应显示绿色 running；浏览器开 http://192.168.1.1:3300"
echo "  仍不行就看：logread -e homebox；/usr/bin/homebox -V"
echo "  ⚠ 别再去「全局设置」点保存——旧版命名 section 会被 LuCI 改写导致再次不启动；"
echo "    本脚本已改成匿名 section，点保存也不会坏了。"
echo
# 刷 LuCI 索引缓存，状态页立刻刷新
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >/dev/null 2>&1 || true
