PonWrt CI —— 编译 naoki66 顶级 ONU 菜单补丁包
基于 gggbin2026/Actions-OpenWrt-AN758X 的 main 分支生成（5 个文件，同名覆盖即可）

【上传位置】在 GitHub 仓库网页点 Add file → Upload files，把文件拖进对应目录：

  diy-part1.sh                              → 仓库根目录（覆盖）
  configs/fiberhome_hg5585f-ct.config        → configs/（覆盖）  ★烽火 HG5585F 电信版
  configs/nokia_xg-040g-md-ubi.config        → configs/（覆盖）  ★诺基亚 XG-040G-MD UBI
  configs/an7581.config                      → configs/（覆盖）   profile 选 all 时用
  .github/workflows/build-ponwrt.yml         → .github/workflows/（覆盖）

  注意：.github 是隐藏目录，解压后若看不到请在文件管理器里开启「显示隐藏项目」。

【改了什么】
1. diy-part1.sh：新增 ADD_ONU 开关，clone naoki66/OpenWrt_ONU_CONFIG，
   删掉 pbs05 pon_userspace feed 里的旧同名包，把 5 个新包放进 package/custom；
   可选应用 firewall4 flowtable 补丁（失败只警告）。REQUIRED 校验加入 luci-app-onu。
2. 三份 config：关掉旧 luci-app-pon / luci-i18n-pon-zh-cn / luci-app-iptv /
   luci-i18n-iptv-zh-cn，打开 luci-app-onu + luci-i18n-onu-zh-cn + omcproxy。
3. build-ponwrt.yml：关键包校验里写死的 luci-app-pon 改为兼容
   luci-app-onu / luci-app-pon 两种写法，否则改造后会直接报错退出。

【编译】Actions → Build PonWrt → soc=an7581，profile 分别选
  fiberhome_hg5585f-ct  /  nokia_xg-040g-md-ubi
其余保持默认（scope=firmware、prebuilt_host=true）。

【注意】
· 首次全量编译可能超过免费 runner 的 350 分钟，建议先跑 Warm Build Cache。
· 刷机前务必备份 factory（烽火）/ bosa、ri（诺基亚）分区里的原厂校准与身份数据，
  丢了 PON 无法注册。A 机型固件绝不能刷到 B 机型。
· 不想要这套 ONU 时，把 diy-part1.sh 里的 ADD_ONU=true 改成 false 即可回退
  （但 config 与 workflow 也要一并回退，否则校验会失败）。
