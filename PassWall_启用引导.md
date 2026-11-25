# PassWall 为什么「启动不了」，以及怎么用起来

## 先说结论：固件没坏，**没节点就不会启动代理**

查上游 `Openwrt-Passwall/openwrt-passwall` 的 `0_default_config` 与 `app.sh`：

```
config global
    option enabled '0'          ← 出厂默认关闭，要你自己勾
    option dns_shunt 'chinadns-ng'
    option dns_redirect '1'
```

`app.sh` 的 `get_config()` 里只有满足下面条件才会把 `ENABLED_DEFAULT_ACL` 置 1：

```sh
[ "$ENABLED" = 1 ] && {
    if [ -n "$NODE" ] && ([ "$(config_get_type $NODE)" = "nodes" ] || ...); then
        ENABLED_DEFAULT_ACL=1
    fi
}
```

**`ENABLED_DEFAULT_ACL=0` 时，`start()` 不会执行 `start_global` / `start_dns` /
nftables 规则**，所以首页 TCP / UDP / DNS / HAPROXY 四张卡片全是
`NOT RUNNING`（中文「未运行」）—— 这是设计，不是故障。

固件已经把 DNS 侧全部准备妥当（`dns_shunt=chinadns-ng` + `dns_redirect=1`，
`chinadns-ng` / `dns2socks` / `xray-core` / `sing-box` 都编入），
**只差你自己的节点**。没有订阅/节点是任何固件都无法预置的。

> 另一个关联因素：本版之前 `上网时间控制Plus` 是 fw3/iptables 老包，
> 它的 `REDIRECT --to-ports 53` 会劫持 DNS，跟 PassWall 抢 53。
> 本包已把它改成 nftables 后端、完全不碰 53，见下文。

---

## 三步启用（照做即可）

### 第 1 步：添加节点

`服务 → PassWall → 节点订阅` → 填你的订阅 URL → **保存并应用** → 点
「更新订阅」。或者 `节点列表 → 添加`，手动填服务器地址 / 端口 /  UUID / 协议。

> 订阅链接、节点是你的账号资源，固件不含、也不该含任何节点。

### 第 2 步：选节点

`节点列表` → 在你要用的那一行点「选择」（或「设为默认」）。
也可以在 `基本设置 → 主要节点` 里选。
选完可以点「测试」看延迟是否通。

### 第 3 步：勾选启用

`基本设置` → **勾选「启用」(Enabled)** → 保存并应用。
controller 会调 `/etc/init.d/passwall restart`。

**注意启动延时**：`0_default_config` 里 `global_delay.start_delay = 60`，
开机自启会先睡 60 秒再启动。手动点启用不用等，但请给它 10~30 秒，
然后刷新页面。

---

## 启用后应该看到

| 位置 | 期望 |
|---|---|
| 首页 4 张卡片 | TCP / UDP / DNS 变 `RUNNING`；HAPROXY 仍是 `N/A`（负载均衡默认没开，正常） |
| `服务 → PassWall → 日志` | 末尾出现 `运行完成！` |
| SSH | `logread -e PSW` / `/etc/init.d/passwall status` |
| DNS | `nslookup google.com 127.0.0.1` 能返回；国内域名也正常 |

## 关于「GitHub / Google 连接失败」

首页那几个「阿里 / 谷歌 / GitHub / YouTube 连接」是**浏览器直连**延迟测试
（JS 直接拉 favicon），不是 PassWall 的状态判定。它显示失败只说明你当前
网络直连不通 —— 这正是要用代理的原因，**配好节点启用后不用管它**。

要代理 GitHub：节点启用后，在 `规则设置` 里把 `gfwlist` / `proxy_host` 打开
（默认 `use_gfw_list='1'` 已开），GitHub 域名会走远端解析与代理。

## 如果启用后仍不起

按顺序查：

```sh
uci get passwall.@global[0].enabled          # 应为 1
uci get passwall.@global[0].node             # 应有节点 section 名
uci show passwall | grep '=nodes'            # 节点段是否存在
/etc/init.d/passwall restart
sleep 20
logread -e PSW | tail -40                    # 看 "全局节点启动失败" / "DNS 启动失败"
nft list table inet miaplus                  # 应存在但不碰 53（本包改好后）
```

`logread` 里出现 **`全局节点启动失败，停止服务`** → 节点配置不完整/服务器不通；
出现 **`DNS 启动失败，停止服务`** → 查 chinadns-ng 是否被别的 53 规则抢了
（本包已修 miaplus，若还有，检查有没有别的插件注册了 `REDIRECT 53`）。

## DNS 链路（本固件）

```
LAN → PassWall 的 dnsmasq 实例(53) → chinadns-ng → 国内直连(223.5.5.5) / 国外远端
```

- 系统 `dnsmasq-full` **保留但只发 DHCP + 缓存**，不配任何上游
- SmartDNS 已整组移除，别再去 PassWall 的 DNS 页选 SmartDNS 分流（没这个二进制，选了必断网）
- 未启用 PassWall 时，系统 dnsmasq 回落 WAN 下发 DNS，不会断网
- `chinadns-ng` 分流没有「国内/国外手动切换」开关，是自动的

## 跟本包其他修复的关系

| 修复 | 对 PassWall 的影响 |
|---|---|
| 上网时间控制 Plus 改 nftables | 去掉 `REDIRECT --to-ports 53`，不再抢 DNS；状态不再靠 `iptables -L` 判活 |
| Homebox 根治 | 无关（:3300 独立端口） |
| 组播逐端口 | 无关（只动 bridge sysfs 与 `inet multicast_allow`，优先级 -10 的 input 链，不动 53） |
| DHCP Snooping | 无关（`bridge` 家族 prerouting 丢 `udp 67→68`，不碰 53） |
