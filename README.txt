PonWrt CI 补丁包 v3 —— ONU 菜单 + rtp2httpd 3.17.2 + iStore 软件中心
基于 gggbin2026/Actions-OpenWrt-AN758X 的 main 分支整份替换。
v3 = v2 的全部改动 + linkease/istore feed，已包含 v1/v2 所有内容。

【上传位置】GitHub 仓库网页 Add file -> Upload files，同名覆盖：

  diy-part1.sh                              -> 仓库根目录（覆盖）
  configs/fiberhome_hg5585f-ct.config        -> configs/（覆盖）  * 烽火 HG5585F CT
  configs/nokia_xg-040g-md-ubi.config        -> configs/（覆盖）  * 诺基亚 XG-040G-MD UBI
  configs/an7581.config                      -> configs/（覆盖）   profile=all 时用
  configs/an7583.config                      -> configs/（覆盖）   以后编 AN7583 用
  .github/workflows/build-ponwrt.yml         -> .github/workflows/（覆盖）

  .github 是隐藏目录，解压后看不到请开启「显示隐藏项目」。
  已传过 v2 的话：workflow 与 4 份 config 有变化，全部都要重新覆盖。

【★ 最容易踩的坑：不要用 FEEDS_CONF】
workflow 第 12 行有个 FEEDS_CONF 环境变量（当前为空）。步骤 4 的逻辑是：
  [ -n "$FEEDS_CONF" ] && cp "$GITHUB_WORKSPACE/$FEEDS_CONF" feeds.conf.default
也就是「整份替换」，不是追加。上游 pbs05/ponwrt 的 feeds.conf.default 有 7 个
有效 feed，其中 pon_drivers / pon_userspace 是整个 PON 功能与 v2 的 ONU 菜单
的基础。如果你照网上 CI 模板新建一份只含 istore 的 feeds.conf.default 并填进
FEEDS_CONF，这两行会被冲掉，PON 包全部消失，固件直接编废。

所以 v3 采用官方 README 的 append 方案，放在 diy-part1.sh 里执行：
  echo >> feeds.conf.default
  echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
  ./scripts/feeds update istore
  ./scripts/feeds install -d y -p istore luci-app-store
执行时机在 workflow 步骤 5（步骤 4 已跑完 feeds update -a / install -a），
脚本末尾会 rm tmp/.packageinfo + make prepare-tmpinfo 重建索引，新包能进索引。

【v3 改了什么】
1) diy-part1.sh
   · 新增 ADD_ISTORE 开关；幂等 append 一行 feed（不重复追加）；
   · 单独 update istore，再按官方命令 install（失败自动退回不带 -d 的写法）；
   · 兜底确认 4 个包都生成了 package/feeds/istore/<pkg> 符号链接；
   · REQUIRED 校验加入 luci-app-store / luci-lib-taskd / luci-lib-xterm / taskd，
     任一包没进索引会在第 5 步直接报错，不会编出「看似成功但没商店」的固件。

2) 4 份 config 末尾新增「21. iStore 软件中心」段：
   CONFIG_PACKAGE_luci-app-store=y / luci-lib-taskd=y / luci-lib-xterm=y /
   taskd=y / luci-compat=y / curl=y
   依赖链：luci-app-store -> luci-lib-taskd -> (luci-lib-xterm, taskd)，
   LUCI_DEPENDS 另带 +curl +tar +libuci-lua +mount-utils，这些由 defconfig
   按 DEPENDS 自动拉入，不必手写。
   * luci-compat：19.07+ 的 iStore 是 Lua LuCI 应用，必须有兼容层。
     两个目标机型原配置已有 =y；an7581 / an7583 这次补上。
   * 界面中文由 istore-ui 前端自带，没有 luci-i18n-store-zh-cn 这个包，别乱加。

3) build-ponwrt.yml：步骤 9 的 defconfig 后校验新增 luci-app-store 检查，
   并打印 feeds.conf / package/feeds/istore / .packageinfo 三项诊断。
   理由：defconfig 会把树里不存在的包符号静默删掉，不加校验会白刷一次。

【编译】Actions -> Build PonWrt -> soc=an7581，其余保持默认，跑两次：
  profile = fiberhome_hg5585f-ct
  profile = nokia_xg-040g-md-ubi
首次建议先跑 Warm Build Cache（免费 runner 350 分钟上限）。

【日志里盯这几行】
  ✅ iStore: 已追加 feed 到 feeds.conf.default
  ✅ iStore: package/feeds/istore/luci-app-store 已就位  （共 4 行）
  ✅ PON 关键包校验通过
  ✅ 状态插件校验通过
若出现 ::error::以下必装插件未进入 tmp/.packageinfo 或
  ::error::以下关键包在 defconfig 后未启用，把第 4/5/9 步日志贴出来。

【注意】
· AN7581 是 arm64，属于 iStore 官方支持的两种架构之一。
· iStore 商店里下载安装的第三方插件，其依赖需自行解决；官方 README 明确说
  「即使系统能装 iStore，里面的插件不一定能装」，精简固件尤其如此。
· 刷机前备份 factory（烽火）/ bosa、ri（诺基亚）原厂校准与身份数据；
  A 机型固件绝不能刷到 B 机型。
· 回退：把 diy-part1.sh 的 ADD_ISTORE 改成 false，同时把 4 份 config 的
  「21. iStore 软件中心」段和 workflow 的 iStore 校验一起删掉，
  只改一处会让 defconfig 校验失败。
