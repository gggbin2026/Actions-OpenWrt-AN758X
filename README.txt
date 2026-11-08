PonWrt CI 修复补丁 v3.1 —— 解决「以下关键包在 defconfig 后未启用: luci-app-store(iStore)」
基于 v3 整份替换，已包含 ONU 菜单 / rtp2httpd 3.17.2 / iStore 全部改动。

========================================================
一、这次失败到底是什么
========================================================
不是编译崩了，是我给 v3 加的那道「防呆校验」主动把流水线拦下了：
步骤 9 跑完 make defconfig 后，.config 里没有
CONFIG_PACKAGE_luci-app-store=y，于是打印
「以下关键包在 defconfig 后未启用，检查 feeds 是否完整」并 exit 1。
它的作用是避免你刷到一个「日志全绿、但根本没有 iStore 菜单」的固件。

关键线索：报错里只有 luci-app-store 一项，ONU-LuCI 和 rtp2httpd
的关键包校验都通过了，日志还出现了
「部分可选包未进入索引（不影响必装插件）」——
说明 diy-part1.sh 的 feed 注入成功、4 个 iStore 包确实进了
tmp/.packageinfo（否则第 5 步的 REQUIRED 就会先 exit 1）。
也就是：包在树里，但 defconfig 之后 .config 里没选中它。

========================================================
二、两个成因（头号嫌疑是第 1 个）
========================================================
【1】configs/ 里 4 个文件没覆盖成功，还是 v2 版
    v3 的 workflow 和 diy-part1.sh 传了，但 configs/*.config 漏传，
    或上传时放到了仓库根目录而不是 configs/ 目录。
    v2 的 config 里有 ONU + rtp2httpd、没有 iStore 段 →
    校验只报 iStore、其他全过，与截图完全吻合。

    10 秒自查：打开仓库 configs/fiberhome_hg5585f-ct.config，
    搜索 luci-app-store，应该能看到「21. iStore 软件中心」那一整段。
    没有 → 就是没传全。

【2】Lua 依赖链被源码基座写成 is not set，defconfig 静默剔除
    源码自带 configs/an7581.config（步骤 6 会先 cp 成 .config）里：
      # CONFIG_PACKAGE_liblua is not set
      # CONFIG_PACKAGE_libuci-lua is not set
      # CONFIG_PACKAGE_luci-compat is not set
      # CONFIG_PACKAGE_luci-lua-runtime is not set
      # CONFIG_PACKAGE_curl is not set
    而 iStore 是带 luasrc/ 的老式 Lua LuCI 应用：
      · ImmortalWrt luci.mk 对带 luasrc/ 的包注入 +luci-lua-runtime
      · luci-app-store 自身 DEPENDS 有 +curl +tar +libuci-lua
        +mount-utils +luci-lib-taskd
      · taskd 还要 +procd +script-utils +coreutils +coreutils-stty
    任何一环不满足，make defconfig 就会把顶层 =y 静默删掉，
    并在 /tmp/defconfig.log 里留下 WARNING（包被剔除的第一现场）。
    这也正好呼应你最开始那个「Unable to load Lua runtime」报错：
    这台固件默认不带 Lua 运行时。

========================================================
三、v3.1 改了什么
========================================================
只动了 .github/workflows/build-ponwrt.yml；其余文件与 v3 相同，
但一并提供，防止你手上是混版。

1) 步骤 6（加载 .config）末尾新增「无条件注入」：
   在 cat 机型配置 >> .config 之后，用 printf 把整条依赖链
   逐行写成 CONFIG_PACKAGE_<name>=y，后写覆盖基座里的 is not set。
   覆盖两种成因：
     · configs/ 漏传 → .config 里也一定会有这些符号
     · 基座 is not set → 被显式 =y 覆盖，依赖链全部满足
   写入清单：luci-app-store / luci-lib-taskd / luci-lib-xterm /
   taskd / luci-compat / luci-lua-runtime / liblua / libuci-lua /
   curl / tar / coreutils / coreutils-stty / script-utils /
   mount-utils / procd / libuci / uci
   （用 printf 而非 heredoc：YAML 块标量带缩进会把空格写进 .config，
     Kconfig 只认行首符号。）

2) 步骤 9 的 iStore 校验诊断从 3 条扩到 7 条，新增：
   · 机型配置里是否真的有 iStore 段
   · .config 中 luci-app-store 的实际状态（是 is not set 还是压根没这行）
   · 5 个 Lua 依赖在 .config 里的实际值
   · /tmp/defconfig.log 里与 store/taskd/lua/curl 相关的 WARNING
   下次再失败，日志能直接指出是「没传 config」还是「依赖不存在」。

3) diy-part1.sh 保持 v3 不变（feed 注入是成功的，不用改）。

========================================================
四、上传清单（同名覆盖）
========================================================
  .github/workflows/build-ponwrt.yml        -> .github/workflows/  ★ 必须重传
  configs/fiberhome_hg5585f-ct.config       -> configs/            ★ 重点确认
  configs/nokia_xg-040g-md-ubi.config       -> configs/
  configs/an7581.config                     -> configs/
  configs/an7583.config                     -> configs/
  diy-part1.sh                              -> 仓库根目录（v3 相同，可不传）

  .github 是隐藏目录，解压后看不到请开启「显示隐藏项目」。
  上传后务必点开 configs/ 里 4 个文件，确认末尾有「21. iStore 软件中心」段。

========================================================
五、编译参数（不变）
========================================================
Actions -> Build PonWrt -> soc=an7581，其余保持默认，跑两次：
  profile = fiberhome_hg5585f-ct
  profile = nokia_xg-040g-md-ubi
注意 profile 表单默认值是 h3c_hm2004-du，千万别点默认直接跑。
首次建议先跑 Warm Build Cache（免费 runner 350 分钟上限）。

日志里盯这几行：
  ✅ iStore: 已追加 feed 到 feeds.conf.default
  ✅ iStore: package/feeds/istore/luci-app-store 已就位（共 4 行）
  ✅ 已无条件注入 iStore / Lua 依赖链（覆盖基座的 is not set）
  ✅ PON 关键包校验通过 / ✅ 状态插件校验通过

========================================================
六、兜底
========================================================
如果只想先拿到固件、不想再被校验拦：把 workflow 里
「if ! grep -q "^CONFIG_PACKAGE_luci-app-store=y" .config; then」
那一段整个注释掉即可编译通过，但固件里不会有 iStore。
另外别忘了展开 /tmp/defconfig.log 的 WARNING 汇总 ——
v3.1 已经把相关行直接打进 Annotations 了。

刷机前照旧备份 factory（烽火）/ bosa、ri（诺基亚）原厂校准与身份数据；
A 机型固件绝不能刷到 B 机型。
