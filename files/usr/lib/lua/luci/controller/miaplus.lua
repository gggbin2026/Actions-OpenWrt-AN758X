module("luci.controller.miaplus",package.seeall)

function index()
	if not nixio.fs.access("/etc/config/miaplus") then
		return
	end

	entry({"admin", "services", "miaplus"}, cbi("base"), _("Internet Access Schedule Control Plus"), 30).dependent = true
	entry({"admin", "services", "miaplus", "status"}, call("act_status")).leaf = true

	entry({"admin", "services", "miaplus", "base"}, cbi("base"), _("Base Setting"), 40).leaf = true
	entry({"admin", "services", "miaplus", "advanced"}, cbi("advanced"), _("Advance Setting"), 50).leaf = true
	entry({"admin", "services", "miaplus", "template"}, cbi("template"), nil).leaf = true
end

-- 2026-11-25 修复：原版是
--   e.running = luci.sys.call("iptables -L INPUT |grep MIAPLUS >/dev/null") == 0
-- 本固件是 fw4 + 纯 nftables，iptables 命令根本不存在，所以状态永远
-- 「未运行」。改成检测 nftables 的 inet miaplus 表（由 /etc/init.d/miaplus
-- 建立、/usr/sbin/miaplus-apply 每分钟重建）。
-- 注意：enable=0 时 init 仍建空表，状态显示 RUNNING 但 chain 为空 =
-- 不限制任何客户端，语义与「服务在跑、规则未启用」一致。
function act_status()
	local e = {}
	e.running = luci.sys.call("nft list table inet miaplus >/dev/null 2>&1") == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
