PonWrt CI 补丁包 v2 —— ONU 菜单 + rtp2httpd v3.17.2
基于 gggbin2026/Actions-OpenWrt-AN758X 的 main 分支整份替换。
v2 = v1（naoki66 顶级 ONU 菜单）+ 官方新版 rtp2httpd，已包含 v1 全部改动。

【上传位置】GitHub 仓库网页 Add file -> Upload files，同名覆盖：

  diy-part1.sh                              -> 仓库根目录（覆盖）
  configs/fiberhome_hg5585f-ct.config        -> configs/（覆盖）  * 烽火 HG5585F CT
  configs/nokia_xg-040g-md-ubi.config        -> configs/（覆盖）  * 诺基亚 XG-040G-MD UBI
  configs/an7581.config                      -> configs/（覆盖）   profile=all 时用
  configs/an7583.config                      -> configs/（覆盖）   以后编 AN7583 用
  .github/workflows/build-ponwrt.yml         -> .github/workflows/（覆盖）

  .github 是隐藏目录，解压后看不到请开启「显示隐藏项目」。
  若已经上传过 v1：workflow 内容未变，只需重新覆盖 diy-part1.sh 和 4 份 config。

【v2 新增了什么】
旧版来自 ImmortalWrt feeds：
  feeds/packages/net/rtp2httpd                 = 3.16.0
  feeds/luci/applications/luci-app-rtp2httpd   = 3.16.0 的 LuCI 前端
新版用 stackia/rtp2httpd 官方 v3.17.2，从官方 openwrt-support/ 取包。

diy-part1.sh：
  · 新增 ADD_RTP2HTTPD 开关，clone 官方 v3.17.2 tag；
  · 删掉 feed 里的旧同名包与 package/feeds 符号链接（含旧 i18n 链接），
    避免两份同名包进索引被挑错；
  · 把 rtp2httpd 和 luci-app-rtp2httpd 放进 package/custom，
    并强制使用官方 Makefile.versioned（固定 3.17.2 + PKG_HASH，
    普通 Makefile 依赖 git describe 和 ../../ 源码树，脱离原仓库编不了）；
  · REQUIRED 校验加入 rtp2httpd / luci-app-rtp2httpd。

config：新增 CONFIG_PACKAGE_rtp2httpd=y 与
  CONFIG_PACKAGE_luci-i18n-rtp2httpd-zh-cn=y，原 luci-app-rtp2httpd=y 保留。

workflow：与 v1 相同，仅把写死的 luci-app-pon 校验改成兼容
  luci-app-onu / luci-app-pon 两种写法。

【编译】Actions -> Build PonWrt -> soc=an7581
  profile = fiberhome_hg5585f-ct  或  nokia_xg-040g-md-ubi
  首次建议先跑 Warm Build Cache（免费 runner 350 分钟上限）。

【不想重编译的快捷办法】在已刷好的设备上 SSH 执行官方一键脚本，
它支持 apk / opkg，会自动卸载 3.16.0 并安装 3.17.2 三个包：
  curl -fsSL https://raw.githubusercontent.com/stackia/rtp2httpd/main/scripts/install-openwrt.sh | sh
脚本会提示选择 GitHub 直连 / gh-proxy / ghfast 镜像；装完 Ctrl+F5 清浏览器缓存。
注意：这是写进 overlay，下次重刷固件会回到 3.16.0；要固化就走上面的编译方案。

【注意】
· 新版 LuCI 是 JS-based，需要较新 LuCI（PonWrt / ImmortalWrt master 满足）。
· 新版配置分 /etc/config/rtp2httpd 与 /etc/rtp2httpd.conf 两个文件；
  ONU 的 IPTV 页也会写 rtp2httpd 相关字段，建议只在一处配置，避免互相覆盖。
· 刷机前备份 factory（烽火）/ bosa、ri（诺基亚）原厂校准与身份数据；
  A 机型固件绝不能刷到 B 机型。
· 回退：ADD_RTP2HTTPD=false 且把 4 份 config 一起还原，否则 defconfig 校验会失败。
