PonWrt CI 修复补丁 v3.2 —— 解决 defconfig 后 .config 里完全没有 luci-app-store
基于 v3.1 整份替换，已包含 ONU 菜单 / rtp2httpd 3.17.2 / iStore 全部改动。

========================================================
一、v3.1 的诊断信息说明了什么（好消息：范围已缩到极小）
========================================================
你贴的日志：
  1) feeds.conf 中 istore 行: 1                  ✅ feed 注入成功
  2) package/feeds/istore: 存在                 ✅ 符号链接建好了
  3) .packageinfo 记录: 1                       ✅ 包被 scan 到了
  4) 机型配置里是否有 iStore 段: 1               ✅ configs 传全了
  5) .config 中 luci-app-store 实际状态: 空     ❌ 决定性线索
  6) Lua 依赖全部 =y                            ✅ 依赖链没问题
  7) defconfig 无 WARNING                       ✅ 不是依赖缺失

第 5 条空 + 第 7 条无 WARNING 合起来只有一个解释：
  tmp/.config-package.in 里没有生成
      config PACKAGE_luci-app-store
  这个 Kconfig 符号。Kconfig 对 .config 中的「未知符号」处理是
  直接丢弃：既不会写成 =y，也不会写 "# ... is not set"，
  更不会打印 WARNING —— 所以「无 WARNING」反而坐实了这一点。

也就是说：包在索引里、依赖全有、config 也写了 =y，
但 Kconfig 符号表里没这个包，make defconfig 就把那行抹掉了。
v3.1 的「无条件注入 =y」方向没错，但符号不存在时 Kconfig 不认。

对照证据：v2 的 ONU 五件套、rtp2httpd 都是直接 cp 进
package/custom/ 的，它们的符号一直在 .config 里（PON 关键包
校验每次都过）。唯独 iStore 用了官方的 feed install 方式。
差别就在这里。

========================================================
二、v3.2 改了什么（两条一起做，一次到位）
========================================================
1) diy-part1.sh —— iStore 不再走 feed，改走 package/custom/
   · 删除 append feeds.conf / feeds update istore / feeds install 那一套
   · 直接 clone https://github.com/istoreos/istore 的 main 分支
   · 把 luci/ 下 4 个包目录拷进 package/custom/：
       luci-app-store / luci-lib-taskd / luci-lib-xterm / taskd
   · 先 rm -rf package/feeds/istore，避免同名包两份 Makefile
   · 复用脚本已有的 clone() 与 PKG_DIR 变量
   · 与 ONU / rtp2httpd 完全同构，彻底绕开 feed 链接、
     scan 深度、metadata 收录的不确定性
   · REQUIRED 校验的 4 个包名不变；脚本末尾原有的
     rm tmp/.packageinfo + make prepare-tmpinfo 保持不变
   · 依赖链（liblua / libuci-lua / luci-lua-runtime / luci-compat /
     curl / tar / coreutils / coreutils-stty / script-utils 等）
     仍由 workflow 步骤 6 无条件注入，不要删

2) build-ponwrt.yml —— 步骤 9 defconfig 之前强制重建 Kconfig 表
   toplevel.mk 的 prepare-tmpinfo 用的是
       [ tmp/.config-package.in -nt tmp/.packageinfo ] || regenerate
   即「符号表比索引新就不重新生成」，旧缓存会让新包的符号不出现。
   所以先删 tmp/.config-package.in / .config-target.in /
   .config-feeds.in / .config-check，再跑一次 prepare-tmpinfo。

   并加一道硬预检：
       grep -q '^config PACKAGE_luci-app-store$' tmp/.config-package.in
   符号不在表里就在第 9 步开头立刻 exit 1，不用等几个小时后白编。
   失败时会打印 package/custom 是否存在、.packageinfo 记录数、
   以及符号表里所有含 store 的 config 行。

3) iStore 失败诊断新增第 8 条：符号表里是否有该 config 项。

========================================================
三、上传清单（同名覆盖）
========================================================
  diy-part1.sh                              -> 仓库根目录       ★ 必须重传
  .github/workflows/build-ponwrt.yml        -> .github/workflows/ ★ 必须重传
  configs/fiberhome_hg5585f-ct.config       -> configs/（v3.1 相同，可不传）
  configs/nokia_xg-040g-md-ubi.config       -> configs/（同上）
  configs/an7581.config / an7583.config     -> configs/（同上）

  .github 是隐藏目录，解压后看不到请开「显示隐藏项目」。
  上传后点开 diy-part1.sh 搜「v3.2」，点开 workflow 搜
  「Kconfig 符号表」，两处都在才算传对。

========================================================
四、怎么跑
========================================================
⚠ 不要点失败那次 run 的 Re-run jobs！GitHub 的 re-run 沿用原始
   commit SHA，不会拉新代码，会原样再失败一次。
   必须：Actions -> Build PonWrt -> 右上角 Run workflow（新 run）。

表单重新填：soc=an7581（默认），其余默认，profile 手动改：
  第一次 fiberhome_hg5585f-ct
  成功后第二次 nokia_xg-040g-md-ubi
（表单默认 profile 是 h3c_hm2004-du，别直接点绿色按钮）

新 run 详情页顶部的 commit 短 SHA 要与仓库首页最新 commit 一致。

日志里盯这几行：
  ✅ iStore: 已放入 package/custom/luci-app-store   （共 4 行）
  ✅ 已无条件注入 iStore / Lua 依赖链
  ✅ Kconfig 符号表已包含 PACKAGE_luci-app-store      ★ 新增，最关键
  ✅ make defconfig 完成
  ✅ PON 关键包校验通过 / ✅ 状态插件校验通过

看到「✅ Kconfig 符号表已包含」就说明这次根因已解决。
缓存（dl/、工具链）会命中，不用清，第二次明显更快。

========================================================
五、还想更省事
========================================================
如果只想先拿到固件，也可以把 workflow 里 iStore 那段校验整个
注释掉，编译会通过但固件里没有 iStore —— 不推荐。

刷机前照旧备份 factory（烽火）/ bosa、ri（诺基亚）原厂校准
与身份数据；A 机型固件绝不能刷到 B 机型。
