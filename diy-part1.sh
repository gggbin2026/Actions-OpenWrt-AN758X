#!/bin/bash
# ================================================================
# diy-part1.sh —— 只做一件事：拉取可选插件到 package/custom
# 2026-11-22 修复：PON 界面用 luci-app-onu（每次全新 clone naoki66 仓库 main 最新提交）；
#                  qwe-qaq/luci-app 补拷 luci-app-igmpproxy（用户要求组播双代理保留）。
# 运行目录: ponwrt 源码根目录（feeds 安装之后、加载 .config 之前）
#
# 用法：把需要的插件开关改成 true，再到 configs/<机型>.config 里
#       把对应 "# CONFIG_PACKAGE_xxx is not set" 改成 "=y"
# ================================================================
echo "=========================================="
echo "拉取可选插件 (diy-part1.sh)"
echo "=========================================="
PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"
# ---------------------------------------------------------
# 插件开关
# 默认开启：Airoha SoC 状态页（config 里已 =y，必须拉否则 defconfig 会剔除）
#
# 温度不再用 luci-app-temp-status —— 由 autocore 的 /sbin/tempinfo 提供，
# 见 files/sbin/tempinfo（概览页「温度」行：CPU / WiFi / PON 温度 + 光功率）
# ---------------------------------------------------------
# ⚠ 下面这些包都在 configs/an7581.config 与 an7583.config 里 =y 了，
#   关掉开关会让 defconfig 把 =y 静默剔除 —— 两处必须一起改。
#
# ⚠ 标了「只用 feeds」的四个，是它们的本体（mosdns / smartdns / xray-core /
#   sing-box）feeds 里已经有同名包，第三方源再拉一份会让索引里出现两个同名
#   Package，package-metadata 按扫描顺序挑一个，行为不可预期。所以只拷 luci
#   前端，本体一律用 feeds 的。
#
#   nft-qos / luci-app-nft-qos / ddns-scripts / luci-app-ddns 四项完全走官方
#   ★ 2026-11-23：DDNS 只留花生壳，Lucky 整组移除（ADD_LUCKY=false）
#   ★ 2026-11-23 插件去重：测速只留 FastNet（Homebox 移除）；
#     5 个「白开且重复」的 ADD_* 开关置 false，避免白 clone。
#   ★ 用户复核：组播代理 omcproxy + igmpproxy **两个都保留**，
#     monorepo 拷包列表恢复为 3 个；IGMP Snooping 由首启脚本开启。
#   feeds（packages + luci），本脚本不 clone，只在 configs/<机型>.config 里写 =y；
#   若 defconfig 报「dependency ... does not exist」，说明该 feed 不带这个包，
#   看 Validate configuration 的 warning，不要在这里补第三方源。
#
#   homebox 不在官方 feeds 里，必须走上面的 clone 段；它和 FastNet 功能有重叠
#   （都是内网测速），但形态不同：FastNet 是 iStore 应用卡片，Homebox 是
#   浏览器直接开 :3300 测「客户端 ↔ 路由」吞吐。两者可共存，端口不冲突。
#
#   luci-app-vantage 同样不在官方 feeds，走上面 clone 段；它依赖的
#   rpcd-mod-ucode / ucode-mod-* 全在底座主仓库，不需要额外 feed。
ADD_AIROHA_NPU=true    # luci-app-airoha-npu：Airoha SoC 状态页（NPU/CPU/Frame Engine/PPE）
# ---------------------------------------------------------
# naoki66/luci-app-airoha —— ★ 本版已移除（2026-11-23，用户「只要 ONU 就行」）
#
#   这是「feed 仓库名」，不是单个插件：里面 7 个 LuCI 包，上一版默认装了
#   4 个（factory / recovery / clients / netmode）。现在整组不要了：
#     · 不再 clone，package/custom 里不出现这 4 个包
#     · 两份 configs/*.config 里对应的 4 个 app + 4 个中文包全改 is not set
#     · workflow 的 Airoha feed 核对改成条件式，不会因缺包报警
#   光猫管理只保留 naoki66/OpenWrt_ONU_CONFIG 的 luci-app-onu 全套。
#
#   ⚠ 下面这行 ADD_AIROHA_NPU=true 是**另一个包**（luanmuc 的 NPU/CPU/PPE
#   状态页），不属于这个 feed，本版保留；连它也不要的话见文件末尾说明。
#   想恢复 feed：把下面 5 行改回 true，并把两份 config 的 8 行 =y 补回来。
# ---------------------------------------------------------
ADD_AIROHA_FEED=false
AIROHA_FEED_BRANCH=main
ADD_AIROHA_FACTORY=false
ADD_AIROHA_RECOVERY=false
ADD_AIROHA_CLIENTS=false
ADD_AIROHA_NETMODE=false
ADD_AIROHA_FANCONTROL=false
ADD_AIROHA_MESH=false
ADD_AIROHA_NPU_V2=false
AIROHA_PKGS=""
ADD_FLUENT=false       # ★ 去重：第三个主题（argon/bootstrap 已够），config 无 =y，白 clone
ADD_FLUENT_LITE=false  # luci-theme-fluent-lite：轻量版（与 fluent 互斥，二选一）
ADD_FLUENT_DASH=false  # luci-mod-fluentdashboard：可选状态概览卡片
ADD_PASSWALL=true      # luci-app-passwall（只用 feeds 的依赖包）
ADD_OPENCLASH=false    # ★ 去重：与 PassWall 同为代理客户端，config 无 =y（白 clone + Ruby 极慢）
ADD_MOSDNS=false       # ★ 去重：DNS 已由 PassWall/chinadns-ng 独占，config 无 =y
ADD_LUCKY=false        # ★ 已移除（2026-11-23「DDNS 只要花生壳」）：Lucky 是另一个 DDNS 客户端
# 「只留花生壳」的实际逻辑在 files/etc/uci-defaults/99-zz-ddns-only-oray（首启执行），
# 不在本脚本：diy 只负责不 clone Lucky，运行期由 uci-defaults 收敛服务商列表。
ADD_TTYD=true          # ★ ttyd + luci-app-ttyd（网页终端，官方 feeds 自带，无需 clone，只写 config）
ADD_ACCESSCONTROL=true # ★ 上网时间控制：用 luci-app-accesscontrol-plus（fw4/nftables 兼容版）
ADD_ACCESSCONTROL_LEGACY=false # 原版 luci-app-accesscontrol：fw3/iptables 时代老包，这套 fw4 固件装了也不生效，默认关
ADD_TAILSCALE=false    # ★ 去重：与 EasyTier 同为异地组网，两者 config 都无 =y → 都关
ADD_OPENLIST=true      # luci-app-openlist2（alist/openlist 挂载）
ADD_SMARTDNS=false     # ★ 已移除（2026-11-23「剔除系统 dns 只要 passwall」）：DNS 全交 PassWall
ADD_RTP2HTTPD=true     # ★ rtp2httpd v3.17.2 + luci-app-rtp2httpd（RTP/UDP/RTSP → HTTP，FCC 快速换台）
ADD_FASTNET=true       # ★ luci-app-fastnet + fastnet（LinEase/iStoreOS 生态，网络测速与链路质量）
                       #   依赖 linkease-app-entry / luci-lib-linkeaseauth，见下方 fastnet 段
ADD_DDNS=true          # ★ ddns-scripts + luci-app-ddns（官方 feeds 自带，无需 clone，只写 config）
ADD_NFT_QOS=true       # ★ nft-qos + luci-app-nft-qos（官方 packages/luci feeds 自带，无需 clone，只写 config）
ADD_HOMEBOX=false      # ★ 去重：与 FastNet 同属测速工具，只留 FastNet（用户明确点名要）
ADD_VANTAGE=true       # ★ luci-app-vantage：实时网络仪表盘【一般插件，不是主题】+ 自带简体中文 po
ADD_EASYTIER=false     # ★ 去重：与 Tailscale 同为异地组网，两者 config 都无 =y → 都关（省 Rust 编译）
ADD_POWEROFF=true      # luci-app-poweroffdevice（关机）
ADD_OWQ_WOL=true       # luci-app-owq-wol（网络唤醒，依赖 etherwake）
ADD_WATCHDOG=true      # luci-app-watchdog（看门狗，包在子目录，需特殊处理）
ADD_TASKPLAN=true      # luci-app-taskplan（定时任务）
ADD_OAF=false          # ⚠ 用户「有风险的就要不了」：kmod-oaf 外部内核模块 6.18 未验证，整组不编入
ADD_LUCI_APP=true       # qwe-qaq/luci-app 仓库（monorepo）
                        #   ├─ luci-app-natmode     NAT 类型三选一（网络 → NAT 类型）
                        #   └─ luci-app-pon-status  PON 光模块卡片（概览页「系统」下一格）
ADD_ONU=true            # ★ naoki66/OpenWrt_ONU_CONFIG：顶级 ONU 菜单（替代旧 luci-app-pon）
# 2026-11-22：旧版在这里用 git apply 找源码树里的 fw4.uc，但 firewall4 是
# PKG_SOURCE_PROTO=git 的外部源码包，fw4.uc 只在 build_dir 解压后才有 ——
# 所以这行永远是「未找到 firewall4/fw4.uc ... 跳过」的假 warning。
# 补丁改由 workflow 的 "Apply optional ONU flowtable patch" 步骤在 make download
# 之后 prepare 出源码再 dry-run 应用（见 build-ponwrt.yml）。这里保持 false。
APPLY_ONU_FW4_PATCH=false
ADD_ISTORE=false        # ★ 已移除 iStore（2026-11-22）：已用 FastNet 替代，
                        #   且它拖进来的 GNU tar / Lua / 压缩库依赖链导致 run #23
                        #   的 tar-1.35-r2.apk 编译失败。关掉后整段 clone 与
                        #   REQUIRED 校验都不会执行（两处都是条件式）。
# 下面这几个开关都能被环境变量覆盖（: ${VAR:=默认} 的写法）：
# workflow 里选了「不拉私有仓库」时会注入 ADD_FTTR=false，整段直接跳过。
: "${ADD_FTTR:=true}"       # FTTR 全家桶总开关（下面的子开关都受它管）★仅 HM2004-DU
: "${ADD_FMCS:=true}"       # h3c-fmcs：Micro-OLT FPGA 内核驱动（kmod-h3c-fmcs）
: "${ADD_FTTR_TOOLS:=true}" # h3c-fttr-tools：fttrd 控制器 + fttrctl（Rust 包）
: "${ADD_FMCS_FW:=true}"    # h3c-fmcs-firmware：FPGA 比特流 FTTR_TOP.sbit
                            # （以上三个都来自 openwrt-fttr 私有仓库，bitstream 由驱动加载）

# 这四个包只对 HM2004-DU 有意义：驱动按 @(TARGET_airoha_an7581) 限定了
# target，界面和后端都围着重型 FTTR 主从设备转。workflow 会把 PROFILE
# 导出成环境变量，非 2004 机型直接跳过，不白花 clone 时间；本地手工跑
# （PROFILE 为空）按 2004 处理。
# ⚠ 不能默认成 h3c_hm2004-du：warm-cache.yml 也会调这个脚本，而它不设
#   PROFILE（缓存与机型无关），更没有私有仓库凭证那三步 —— 默认成 h3c 会让
#   它去 clone 私有仓库 openwrt-fttr，然后因 "could not read Username" 失败。
#   本地手工跑 h3c 机型时，显式 PROFILE=h3c_hm2004-du 即可。
FTTR_PROFILE="${PROFILE:-none}"

clone() {  # clone <url> <dir> [branch]
  local url="$1" dir="$2" br="$3"
  [ -d "$dir" ] && { echo "已存在，跳过: $dir"; return 0; }
  echo "--- git clone $url -> $dir ---"
  if [ -n "$br" ]; then
    git clone --depth 1 -b "$br" "$url" "$dir" 2>&1 | tail -3
  else
    git clone --depth 1 "$url" "$dir" 2>&1 | tail -3
  fi
  if [ -d "$dir" ]; then
    echo "✅ 克隆成功: $dir"
    return 0
  fi
  echo "::error::克隆失败: $url"
  return 1
}
# =========================================================
# qwe3017/luci-app —— 两个 LuCI 插件的来源
#
# 这是一个 monorepo，结构为：
#   luci-app/
#   ├── luci-app-natmode/
#   ├── luci-app-pon-status/
#   └── luci-app-igmpproxy/   ← ★ 2026-11-23 用户复核：组播双代理都保留，恢复拷入
#
# ⚠ 三个都拷：igmpproxy 是用户明确要保留的 IPv4 组播代理，
#   缺了它 config 里的 =y 会被 defconfig 静默剔除，LuCI 少一张配置页。
# =========================================================
if [ "$ADD_LUCI_APP" = "true" ]; then
  LUCI_APP_URL="https://github.com/qwe-qaq/luci-app"
  LUCI_APP_TMP="$(mktemp -d)/luci-app"
  if ! clone "$LUCI_APP_URL" "$LUCI_APP_TMP" main; then
    echo "::error::qwe-qaq/luci-app 拉取失败，natmode / pon-status / igmpproxy 会被 defconfig 剔除"
    exit 1
  fi
  for p in luci-app-natmode luci-app-pon-status luci-app-igmpproxy; do
    if [ ! -f "$LUCI_APP_TMP/$p/Makefile" ]; then
      echo "::error::$LUCI_APP_TMP/$p/Makefile 不存在，包无法被索引"
      exit 1
    fi
    rm -rf "$PKG_DIR/$p"
    cp -r "$LUCI_APP_TMP/$p" "$PKG_DIR/"
    echo "✅ 已拷贝: $p  (版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/$p/Makefile" 2>/dev/null | sed 's/PKG_VERSION:=//'))"
  done
  rm -rf "$LUCI_APP_TMP"
fi

# =========================================================
# ★ naoki66/OpenWrt_ONU_CONFIG —— 顶级 ONU 菜单（重构版 PON 用户态）
#
# 源码 pbs05/ponwrt 自带的 pon_userspace feed 是旧栈：
#   luci-app-pon + luci-app-iptv + airoha-pon-daemons / ponctl / pon-debug
# naoki66 是它的 fork 重构版：
#   · luci-app-pon  → 改名 luci-app-onu，提升为顶级菜单
#   · luci-app-iptv → 吸收进 luci-app-onu（onu-internet / onu-iptv / onu-voice）
#   · airoha-pond / ponctl / debug 同步重构（auth_mode、完整简体中文等）
#   · 新增 luci-app-pon-status（概览页 PON 卡片）
#
# ⚠ 同名包不能两份同时进索引（package-metadata 会挑错）。所以：
#   ① 删掉 feeds/pon_userspace 里的旧同名包及 package/feeds 符号链接；
#   ② 把新版 5 个包全部放进 package/custom/，由 prepare-tmpinfo 扫描；
#   ③ 覆盖 ADD_LUCI_APP 拷进来的旧版 luci-app-pon-status。
# =========================================================
if [ "$ADD_ONU" = "true" ]; then
  # ★ 版本策略：不锁 commit、不锁 tag，每次 CI 都用 --depth 1 全新 clone 一次
  #   main 分支当前 HEAD，编译出来的 luci-app-onu 就是上游最新版（apk 包随固件一起出）。
  #   想临时试别的分支：在 workflow 里传环境变量 ONU_BRANCH，或直接改下面这个默认值。
  ONU_URL="https://github.com/naoki66/OpenWrt_ONU_CONFIG"
  : "${ONU_BRANCH:=main}"
  ONU_TMP="$(mktemp -d)/OpenWrt_ONU_CONFIG"
  if ! clone "$ONU_URL" "$ONU_TMP" "$ONU_BRANCH"; then
    echo "::error::naoki66/OpenWrt_ONU_CONFIG 拉取失败，luci-app-onu 会被 defconfig 剔除"
    exit 1
  fi
  # 把本次实际拉到的提交打进日志 —— 用来核对「是不是最新」，别再靠猜
  echo "ℹ ONU 源: ${ONU_URL} @ ${ONU_BRANCH}"
  echo "ℹ ONU 提交: $(git -C "$ONU_TMP" rev-parse --short HEAD) · $(git -C "$ONU_TMP" log -1 --format='%ci %s')"

  for p in airoha-pon-daemons airoha-ponctl airoha-pon-debug luci-app-pon luci-app-iptv; do
    rm -rf "feeds/pon_userspace/$p" "package/feeds/pon_userspace/$p"
  done
  rm -rf "$PKG_DIR/luci-app-pon-status" "package/feeds/custom/luci-app-pon-status"

  for p in airoha-pon-daemons airoha-ponctl airoha-pon-debug luci-app-onu luci-app-pon-status; do
    if [ ! -f "$ONU_TMP/$p/Makefile" ]; then
      echo "::error::$ONU_TMP/$p/Makefile 不存在（上游改了目录结构？）"
      exit 1
    fi
    rm -rf "$PKG_DIR/$p"
    cp -a "$ONU_TMP/$p" "$PKG_DIR/$p"
    echo "✅ ONU: 已拷贝 $p"
  done

  # 可选：firewall4 flowtable 补丁（PPPoE / VLAN 上联的硬件卸载）。
  # 失败只 warning —— ONU 菜单照常能编出来，不阻断本步骤。
  if [ "$APPLY_ONU_FW4_PATCH" = "true" ]; then
    ONU_PATCH="$ONU_TMP/patches/firewall4/010-fw4-zone-device-flowtable.patch"
    FW4_DIR="$(find feeds package -maxdepth 6 -type d -name firewall4 -print -quit 2>/dev/null)"
    if [ -f "$ONU_PATCH" ] && [ -n "$FW4_DIR" ] && [ -f "$FW4_DIR/root/usr/share/ucode/fw4.uc" ]; then
      if (cd "$FW4_DIR" && git apply --check "$ONU_PATCH" 2>/dev/null); then
        (cd "$FW4_DIR" && git apply "$ONU_PATCH") && echo "✅ ONU: 已应用 firewall4 flowtable 补丁"
      else
        echo "::warning::firewall4 补丁不适用当前源码（版本差异），跳过；ONU 菜单不受影响"
      fi
    else
      echo "::warning::未找到 firewall4/fw4.uc 或补丁文件，跳过 flowtable 补丁"
    fi
  fi
  rm -rf "$ONU_TMP"
fi

# =========================================================
# naoki66/luci-app-airoha —— Airoha/Gemtek 专用 LuCI feed【本版已移除】
#
# 2026-11-23 用户要求「luci-app-airoha 也不要了，只要 ONU 就行」：
#   ADD_AIROHA_FEED=false，整段不执行，不 clone、不拷包、po 改名也不跑。
#   保留代码只是留个可逆的开关，将来想恢复改上面 5 行 + 两份 config 即可。
# 原说明：7 个包（npu / factory / recovery / fancontrol / netmode / mesh-conf /
# clients），只把开关打开的包拷进 package/custom/，不用的不进索引。
#
# ⚠ po 改名：luci.mk 第 9 行
#     LUCI_BASENAME ?= $(patsubst luci-$(LUCI_TYPE)-%,%,$(LUCI_NAME))
#   即 luci-app-airoha-factory → basename「airoha-factory」，中文包叫
#   luci-i18n-airoha-factory-zh-cn，且 po 文件必须是「airoha-factory.po」。
#   naoki66 上游 5 个包的 po 都叫「luci-app-xxx.po」，不改名的会生成
#   「luci-app-xxx.zh-cn.lmo」，前端找不到 → 菜单是英文。
#   （luci-app-clients 上游已是 clients.po，下面逻辑幂等，不会重复改名。）
# =========================================================
if [ "$ADD_AIROHA_FEED" = "true" ]; then
  AIROHA_URL="https://github.com/naoki66/luci-app-airoha"
  AIROHA_TMP="$(mktemp -d)/luci-app-airoha"
  if ! clone "$AIROHA_URL" "$AIROHA_TMP" "$AIROHA_FEED_BRANCH"; then
    echo "::error::naoki66/luci-app-airoha 拉取失败，Airoha feed 的 4 个 LuCI 包会被 defconfig 剔除"
    exit 1
  fi
  echo "ℹ Airoha feed: ${AIROHA_URL} @ ${AIROHA_FEED_BRANCH}"
  echo "ℹ Airoha feed 提交: $(git -C "$AIROHA_TMP" rev-parse --short HEAD) · $(git -C "$AIROHA_TMP" log -1 --format='%ci %s')"

  AIROHA_PKGS=""
  [ "$ADD_AIROHA_FACTORY"    = "true" ] && AIROHA_PKGS="$AIROHA_PKGS luci-app-airoha-factory"
  [ "$ADD_AIROHA_RECOVERY"   = "true" ] && AIROHA_PKGS="$AIROHA_PKGS luci-app-airoha-recovery"
  [ "$ADD_AIROHA_CLIENTS"    = "true" ] && AIROHA_PKGS="$AIROHA_PKGS luci-app-clients"
  [ "$ADD_AIROHA_NETMODE"    = "true" ] && AIROHA_PKGS="$AIROHA_PKGS luci-app-netmode"
  [ "$ADD_AIROHA_FANCONTROL" = "true" ] && AIROHA_PKGS="$AIROHA_PKGS luci-app-airoha-fancontrol"
  [ "$ADD_AIROHA_MESH"       = "true" ] && AIROHA_PKGS="$AIROHA_PKGS luci-app-mesh-conf"
  if [ "$ADD_AIROHA_NPU_V2" = "true" ]; then
    echo "::error::ADD_AIROHA_NPU_V2 与现有 luanmuc/luci-app-airoha-npu 包名相同，两份同名包进索引会互相覆盖"
    echo "        要整体换源：先把 ADD_AIROHA_NPU 改成 false 并删掉 luanmuc 的 clone 段，再开这个"
    exit 1
  fi

  for p in $AIROHA_PKGS; do
    if [ ! -f "$AIROHA_TMP/$p/Makefile" ]; then
      echo "::error::$AIROHA_TMP/$p/Makefile 不存在（上游改结构了？）"
      exit 1
    fi
    bn="${p#luci-app-}"
    rm -rf "$PKG_DIR/$p" "package/feeds/custom/$p"
    cp -a "$AIROHA_TMP/$p" "$PKG_DIR/$p"
    echo "✅ Airoha feed: 已放入 package/custom/$p (basename=$bn)"

    PODIR="$PKG_DIR/$p/po/zh_Hans"
    if [ -d "$PODIR" ] && [ ! -f "$PODIR/$bn.po" ]; then
      src_po="$(find "$PODIR" -maxdepth 1 -type f -name '*.po' -print -quit)"
      if [ -n "$src_po" ]; then
        mv "$src_po" "$PODIR/$bn.po"
        echo "✅ Airoha feed: po 改名 $(basename "$src_po") -> $bn.po → 可生成 luci-i18n-$bn-zh-cn"
      fi
    fi
  done
  rm -rf "$AIROHA_TMP"
fi

# =========================================================
# ★ iStore 软件中心 v3.2 —— 直接放进 package/custom/
#
# 为什么不再用官方的 feed install 方式：
#   v3 / v3.1 用 `src-git istore` + `feeds install` 后，CI 诊断显示
#     · feeds.conf 有 istore 行          ✅
#     · package/feeds/istore 存在        ✅
#     · tmp/.packageinfo 有这个包        ✅
#     · 机型 config 写了 =y              ✅
#     · Lua / curl 依赖全部 =y           ✅
#     · defconfig 无任何 WARNING         ✅
#   但 defconfig 之后 .config 里连一行 luci-app-store 都没有，
#   grep 不到 =y、也 grep 不到 "is not set" —— 说明
#   tmp/.config-package.in 里根本没有生成
#   `config PACKAGE_luci-app-store` 这个 Kconfig 符号。
#   Kconfig 对 .config 中的未知符号会直接丢弃：既不写 =y，
#   也不写 "is not set"，更不会打 WARNING。
#
#   对照：v2 的 ONU 五件套和 rtp2httpd 都是 cp 进 package/custom/ 的，
#   它们的符号一直在 .config 里（PON 关键包校验每次都过）。
#   所以这里改成和它们完全同构，彻底绕开 feed 链接 / scan 深度 /
#   metadata 收录的不确定性。
#
# ⚠ package/custom/ 与 package/feeds/istore/ 不能同时存在同名包，
#   否则 scan 会看到两份 Makefile。下面先删链接再拷贝。
# =========================================================
if [ "$ADD_ISTORE" = "true" ]; then
  ISTORE_TMP="$(mktemp -d)/istore"
  ISTORE_PKGS="luci-app-store luci-lib-taskd luci-lib-xterm taskd"

  if ! clone https://github.com/istoreos/istore "$ISTORE_TMP" main; then
    echo "::error::iStore 源码 clone 失败（GitHub 拉取不通？）"
    rm -rf "$ISTORE_TMP"
    exit 1
  fi

  rm -rf package/feeds/istore          # 防止同名包两份
  mkdir -p "$PKG_DIR"

  for p in $ISTORE_PKGS; do
    src="$ISTORE_TMP/luci/$p"
    if [ ! -f "$src/Makefile" ]; then
      echo "::error::iStore 源码里缺 luci/$p/Makefile，上游改结构了？"
      rm -rf "$ISTORE_TMP"
      exit 1
    fi
    rm -rf "$PKG_DIR/$p"
    cp -a "$src" "$PKG_DIR/$p"
    echo "✅ iStore: 已放入 package/custom/$p"
  done

  rm -rf "$ISTORE_TMP"

  # 依赖链由 defconfig 按 DEPENDS 拉入，但源码基座把 liblua/libuci-lua/
  # luci-lua-runtime/luci-compat/curl 写成 is not set，仍由 workflow 步骤 6
  # 无条件注入（见 build-ponwrt.yml）。
fi

# =========================================================
# h3c-fmcs / h3c-fttr-tools / h3c-fmcs-firmware —— FTTR 后端三件套 ★HM2004-DU 专属
# 源：qwe-qaq/openwrt-fttr（私有仓库）
# ⚠ 这里必须用「裸 URL」：凭证由 workflow 的 GIT_ASKPASS 在认证时回调注入，
#   千万别拼 token —— clone 的 echo 会把它打进日志。
# ⚠ 该仓库是 feed 形态（根目录直接是三个包目录），按目录名拷进 package/custom/
#   即可；目录名必须等于包名（PKG_NAME ?= $(notdir $(CURDIR)）），否则 config
#   里的 CONFIG_PACKAGE_xxx 对不上。
#   h3c-fmcs           KernelPackage → 索引里叫 kmod-h3c-fmcs，DEPENDS 限定
#                      @(TARGET_airoha_an7581)，另依赖 +kmod-spi-gpio
#   h3c-fttr-tools     Rust 包，硬 include feeds/packages/lang/rust/rust-package.mk
#   h3c-fmcs-firmware  纯数据包，FPGA 比特流 → /lib/firmware/FTTR_TOP.sbit
# ⚠ h3c-fmcs 是 KernelPackage，索引里的名字是 kmod-h3c-fmcs。下面的包索引
#   校验内置了这层映射（pkgname_of），看到的是 ✅ h3c-fmcs → kmod-h3c-fmcs。
# =========================================================
if [ "$ADD_FTTR" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ]; then
  # 仓库与分支由 workflow 注入，本地手工跑时回退到下面的默认值
  FTTR_FEED_URL="https://github.com/${PRIVATE_REPO:-qwe-qaq/openwrt-fttr}"
  FTTR_FEED_BRANCH="${PRIVATE_REPO_BRANCH:-main}"
  FTTR_FEED_TMP="$(mktemp -d)/openwrt-fttr"
  if ! clone "$FTTR_FEED_URL" "$FTTR_FEED_TMP" "$FTTR_FEED_BRANCH"; then
    echo "::error::openwrt-fttr 拉取失败：${FTTR_FEED_URL} (分支 ${FTTR_FEED_BRANCH})，kmod-h3c-fmcs / h3c-fttr-tools / h3c-fmcs-firmware 会被 defconfig 剔除"
    echo "        公开仓库失败=仓库/分支名不对；私有仓库缺凭证=优先查 GitHub App（PRIVATE_SOURCE_APP_ID / PRIVATE_SOURCE_APP_PRIVATE_KEY，App 要装到该仓库且 Contents: Read-only），回退才看 Secret PRIVATE_REPO_TOKEN 是否有效（PAT 需对该仓库有 Contents 读权限）"
    exit 1
  fi

  # h3c-fttr-tools 硬 include 了 feeds/packages/lang/rust/rust-package.mk，
  # 这个文件不在的话 dump 直接失败、包静默不进索引。
  # 与其等到 defconfig 把它剔掉才发现，不如在这里就报错退出。
  if [ "$ADD_FTTR_TOOLS" = "true" ] && [ ! -f feeds/packages/lang/rust/rust-package.mk ]; then
    echo "::error::未找到 feeds/packages/lang/rust/rust-package.mk，h3c-fttr-tools 无法索引"
    echo "        确认 packages feed 已 update + install；或把 ADD_FTTR_TOOLS 置为 false"
    exit 1
  fi

  FTTR_FEED_PKGS=""
  [ "$ADD_FMCS" = "true" ]       && FTTR_FEED_PKGS="$FTTR_FEED_PKGS h3c-fmcs"
  [ "$ADD_FTTR_TOOLS" = "true" ] && FTTR_FEED_PKGS="$FTTR_FEED_PKGS h3c-fttr-tools"
  [ "$ADD_FMCS_FW" = "true" ]    && FTTR_FEED_PKGS="$FTTR_FEED_PKGS h3c-fmcs-firmware"

  for p in $FTTR_FEED_PKGS; do
    if [ ! -f "$FTTR_FEED_TMP/$p/Makefile" ]; then
      echo "::error::$FTTR_FEED_TMP/$p/Makefile 不存在（上游改结构了？）"
      exit 1
    fi
    rm -rf "$PKG_DIR/$p"
    cp -a "$FTTR_FEED_TMP/$p" "$PKG_DIR/$p"
    echo "✅ 已拷贝: $p  (版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/$p/Makefile" 2>/dev/null | sed 's/PKG_VERSION:=//'))"
  done
  rm -rf "$FTTR_FEED_TMP"
fi

# =========================================================
# luci-app-fttr —— FTTR 管理界面（网络 → FTTR）★HM2004-DU 专属
# 源：LazuliKao/luci-app-fttr（monorepo，包在 package/luci-app-fttr/ 子目录）
# ⚠ 不能整仓丢进 package/custom：buildroot 只扫到 -maxdepth 5，整仓会把
#   src/、package/ 一起扫，包符号还对不上。必须拷子目录。
# 依赖 +luci-base +rpcd +ucode +ucode-mod-fs +h3c-fttr-tools，后者不在
# ImmortalWrt feeds —— 见下方硬校验。
# =========================================================
if [ "$ADD_FTTR" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ]; then
  FTTR_TMP="$(mktemp -d)/fttr"
  if ! clone https://github.com/LazuliKao/luci-app-fttr "$FTTR_TMP" main; then
    echo "::error::luci-app-fttr 拉取失败，config 里的 =y 会被 defconfig 剔除"
    exit 1
  fi
  if [ ! -f "$FTTR_TMP/package/luci-app-fttr/Makefile" ]; then
    echo "::error::$FTTR_TMP/package/luci-app-fttr/Makefile 不存在（上游改结构了？）"
    exit 1
  fi

  rm -rf "$PKG_DIR/luci-app-fttr"
  cp -a "$FTTR_TMP/package/luci-app-fttr" "$PKG_DIR/luci-app-fttr"

  # Windows 检出会丢 executable bit，rpcd 插件与 hl202 脚本执行不了 → 页面全空。
  # Makefile 里虽然有 Build/Prepare 的 chmod，这里先在源码树补一道更保险。
  chmod 0755 "$PKG_DIR/luci-app-fttr/root/usr/libexec/fttr-hl202" \
             "$PKG_DIR/luci-app-fttr/root/usr/libexec/rpcd/luci.fttr" 2>/dev/null || true

  # po/zh_Hans 已经是 fttr.po（LUCI_BASENAME 命名），不用像 airoha-npu 那样改名
  echo "✅ 已拷贝: luci-app-fttr (版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/luci-app-fttr/Makefile" 2>/dev/null | sed 's/PKG_VERSION:=//'))"
  rm -rf "$FTTR_TMP"
fi


# --- Airoha SoC 状态页（NPU 卸载 / CPU 频率 / Frame Engine / PPE 流表）---
# 包名由目录名决定（luci.mk: PKG_NAME ?= $(notdir ${CURDIR})），
# 目录必须是 luci-app-airoha-npu，否则 config 里的符号对不上。
#
# 源用 luanmuc/luci-app-airoha-npu（rchen14b 的 fork 改进版）：
#   - 自带 po/zh_Hans 完整中文翻译（48 条）
#   - 无 rchen14b 那种「根目录 + 同名子目录」重复结构，feed 索引不会中断
#   - 修了 luci.mk 的 include 路径、加了独立 CPU 温度与 PLL 备用频率
if [ "$ADD_AIROHA_NPU" = "true" ]; then
  if ! clone https://github.com/luanmuc/luci-app-airoha-npu "$PKG_DIR/luci-app-airoha-npu" main; then
    echo "::error::luci-app-airoha-npu 拉取失败，后续 defconfig 会静默剔除该包"
    exit 1
  fi
  # 包名校验：Makefile 必须存在，否则 buildroot 扫不到这个包
  if [ ! -f "$PKG_DIR/luci-app-airoha-npu/Makefile" ]; then
    echo "::error::$PKG_DIR/luci-app-airoha-npu/Makefile 不存在，包无法被索引"
    exit 1
  fi
  echo "   版本: $(grep -m1 '^PKG_VERSION' "$PKG_DIR/luci-app-airoha-npu/Makefile" 2>/dev/null)"
  # =========================================================
  # 关键：po 文件名必须改成 airoha-npu.po
  #   luci.mk 的 i18n 规则按 po 主名生成 lmo，运行时却按 LUCI_BASENAME
  #   （= airoha-npu）查找。上游两份 po 都叫 luci-app-airoha-npu.po，会生成
  #   luci-app-airoha-npu.zh-cn.lmo → 前端找不到 → 中文不生效。
  # =========================================================
  PODIR="$PKG_DIR/luci-app-airoha-npu/po"
  if [ -f "$PODIR/zh_Hans/luci-app-airoha-npu.po" ]; then
    # 确保 Language 头是 zh_Hans（上游头部缺该字段时 po2lmo 可能识别异常）
    grep -q '^"Language:' "$PODIR/zh_Hans/luci-app-airoha-npu.po" || \
      sed -i 's/^msgstr ""$/msgstr ""\n"Language: zh_Hans\\n"/' "$PODIR/zh_Hans/luci-app-airoha-npu.po"
    mv "$PODIR/zh_Hans/luci-app-airoha-npu.po" "$PODIR/zh_Hans/airoha-npu.po"
    echo "✅ po 改名: luci-app-airoha-npu.po -> airoha-npu.po（luci.mk 按 LUCI_BASENAME 查找）"
  fi
  if [ -f "$PODIR/es/luci-app-airoha-npu.po" ]; then
    mv "$PODIR/es/luci-app-airoha-npu.po" "$PODIR/es/airoha-npu.po"
  fi
  echo "   po/zh_Hans: $(ls -1 "$PODIR/zh_Hans/" 2>/dev/null | tr '\n' ' ')"
fi

# --- passwall ---
# 源已从 xiaorouji 迁到 Openwrt-Passwall 组织（旧地址 404）。
# ⚠ 只拷 luci-app-passwall 子目录：openwrt-passwall-packages 是 monorepo，
#   里面 xray-core / sing-box / hysteria / naiveproxy / shadowsocks-rust …
#   全部与 feeds 同名，整仓拷进来就是两份同名包。依赖一律用 feeds 的。
if [ "$ADD_PASSWALL" = "true" ]; then
  PW_TMP="$(mktemp -d)/pw"
  if clone https://github.com/Openwrt-Passwall/openwrt-passwall "$PW_TMP" main \
     && [ -f "$PW_TMP/luci-app-passwall/Makefile" ]; then
    rm -rf "$PKG_DIR/luci-app-passwall"
    cp -r "$PW_TMP/luci-app-passwall" "$PKG_DIR/"
    echo "✅ 已拷贝: luci-app-passwall"
  else
    echo "::error::luci-app-passwall 拉取失败或结构变化"
  fi
  rm -rf "$PW_TMP"
fi
# --- openclash ---
if [ "$ADD_OPENCLASH" = "true" ]; then
  echo "::warning::OpenClash 会触发 Ruby/Rust 编译，耗时极长"
  clone https://github.com/vernesong/OpenClash "$PKG_DIR/OpenClash" master
  mv "$PKG_DIR/OpenClash/luci-app-openclash" "$PKG_DIR/luci-app-openclash" 2>/dev/null
  rm -rf "$PKG_DIR/OpenClash"
fi
# --- mosdns ---
# ⚠ 只拷 luci-app-mosdns 子目录：仓库里还带 mosdns 本体与 v2ray-geodata，
#   两个都与 feeds 同名。本体用 feeds 的。
if [ "$ADD_MOSDNS" = "true" ]; then
  MD_TMP="$(mktemp -d)/mosdns"
  if clone https://github.com/sbwml/luci-app-mosdns "$MD_TMP" v5 \
     && [ -f "$MD_TMP/luci-app-mosdns/Makefile" ]; then
    rm -rf "$PKG_DIR/luci-app-mosdns" "$PKG_DIR/geo2txt"
    cp -r "$MD_TMP/luci-app-mosdns" "$PKG_DIR/"
    # geo2txt 是 luci-app-mosdns 的硬依赖（LUCI_DEPENDS 里 +geo2txt），
    # feeds 里没有同名包，必须一起拷进来，否则索引时报
    # "has a dependency on 'geo2txt', which does not exist"
    if [ -f "$MD_TMP/geo2txt/Makefile" ]; then
      cp -r "$MD_TMP/geo2txt" "$PKG_DIR/"
      echo "✅ 已拷贝: geo2txt（luci-app-mosdns 依赖）"
    else
      echo "::warning::mosdns 仓库里没有 geo2txt，luci-app-mosdns 会缺这个依赖"
    fi
    echo "✅ 已拷贝: luci-app-mosdns（本体用 feeds）"
  else
    echo "::error::luci-app-mosdns 拉取失败或结构变化"
  fi
  rm -rf "$MD_TMP"
fi
# --- lucky ---
# 上游 monorepo 里两个包：lucky（本体，DDNS/端口转发服务）+ luci-app-lucky（前端）。
# 前端 LUCI_DEPENDS:=+lucky，两个目录都要拷，否则索引报「依赖 watchdog/lucky 不存在」。
# 自带 po/zh_Hans/lucky.po → luci.mk 生成 luci-i18n-lucky-zh-cn。
if [ "$ADD_LUCKY" = "true" ]; then
  echo "::warning::ADD_LUCKY 又被打开了 —— 本版「DDNS 只留花生壳」，"
  echo "        configs/*.config 里 lucky 三行仍是 is not set，=y 不会生效；"
  echo "        确认要恢复 Lucky 需同时改 config 三行 + 关闭 99-zz-ddns-only-oray"
  LK_TMP="$(mktemp -d)/lucky"
  if clone https://github.com/sirpdboy/luci-app-lucky "$LK_TMP" main; then
    for p in lucky luci-app-lucky; do
      [ -f "$LK_TMP/$p/Makefile" ] || { echo "::warning::lucky monorepo 缺 $p（上游改结构了？）"; continue; }
      rm -rf "$PKG_DIR/$p" && cp -r "$LK_TMP/$p" "$PKG_DIR/"
      echo "✅ 已拷贝: $p"
    done
    [ -f "$PKG_DIR/luci-app-lucky/po/zh_Hans/lucky.po" ] \
      || echo "::warning::缺 po/zh_Hans/lucky.po，中文包 luci-i18n-lucky-zh-cn 可能不生成"
  else
    echo "::error::luci-app-lucky 拉取失败"
  fi
  rm -rf "$LK_TMP"
fi
# --- tailscale ---
if [ "$ADD_TAILSCALE" = "true" ]; then
  clone https://github.com/asvow/luci-app-tailscale "$PKG_DIR/luci-app-tailscale" main
fi
# --- openlist2 ---
if [ "$ADD_OPENLIST" = "true" ]; then
  clone https://github.com/sbwml/luci-app-openlist2 "$PKG_DIR/luci-app-openlist2" main
fi

# --- homebox（已停用：插件去重只留 FastNet）-----------------------------
# ★ 2026-11-23：下面这段保留但 ADD_HOMEBOX=false，不会执行。
#   保留源码便于三处回退（config 三行 =y + ADD_HOMEBOX=true + 恢复 files 三件套）。
# ------------------------------------------------------------------------
# --- homebox（浏览器内网测速 http://<路由IP>:3300）-----------------------
# 两个包来自两个仓库，都只拷需要的子目录，避免和 feeds 里同名包冲突：
#   sirpdboy/netspeedtest/homebox/Makefile  -> homebox 本体（预编译 musl 二进制）
#   selfcan/luci-app-homebox                -> LuCI 界面（LUCI_DEPENDS:=+homebox）
#
# 为什么选预编译版：jjm2473/openwrt-apps 与 xiangfeidexiaohuo 的源码版要
# golang/host + homebox/host（npm 编译前端），Build/Configure 还会 go get /@latest
# 联网拉依赖 —— 350 分钟的 job 里最容易挂的就是这种。sirpdboy 版只从
# Releases 下载 homebox-linux-arm64-musl-v1.0.1.tar.gz 解压到 /usr/bin/homebox，
# DEPENDS:=@(i386||x86_64||arm||aarch64)，AN758x 是 aarch64，满足。
# PKG_HASH 已与本仓库 v1.0.1 release asset 的 sha256 digest 逐个比对一致。
#
# ⚠ 预编译版 Makefile 只装二进制，不带 /etc/config/homebox 与 /etc/init.d/homebox；
#   而 luci-app-homebox 的 controller 要求 /etc/config/homebox 存在才显示菜单。
#   这两个文件由本仓库 files/ 直接打进 rootfs（见 files/etc/config/homebox、
#   files/etc/init.d/homebox、files/etc/uci-defaults/99-zz-homebox）。
# ------------------------------------------------------------------------
if [ "$ADD_HOMEBOX" = "true" ]; then
  HB_TMP="$(mktemp -d)/netspeedtest"
  if clone https://github.com/sirpdboy/netspeedtest "$HB_TMP" main \
     && [ -f "$HB_TMP/homebox/Makefile" ]; then
    rm -rf "$PKG_DIR/homebox" && cp -r "$HB_TMP/homebox" "$PKG_DIR/"
    echo "✅ 已拷贝: homebox（预编译二进制版）"
  else
    echo "::error::homebox 本体拉取失败或结构变化"
  fi
  if clone https://github.com/selfcan/luci-app-homebox "$PKG_DIR/luci-app-homebox" main; then
    echo "✅ 已拷贝: luci-app-homebox（含中文 po）"
  else
    echo "::error::luci-app-homebox 拉取失败"
  fi
fi

# --- luci-app-vantage（实时网络仪表盘，一般插件，不是主题）-----------------
# 上游 anothaDev/luci-theme-vantage 同时提供三个包：
#   luci-theme-vantage      → 主题（改 LuCI 外观/登录页/Ctrl+K）      ❌ 明确不装
#   luci-app-vantage        → 仪表盘 app（一般插件，独立可用）         ✅ 本段只装它
#   luci-app-vantage-aps    → 配对其它 AP 的可选扩展                  ❌ 不装
#
# ⚠ 为什么不装主题：恩山 8497992 帖 3#/4#/7# 有人反馈「更新后台进不去」，
#   点评归因为「vantage 界面」，长按 30 秒重置才恢复。用户明确要求「不是主题，
#   就是一般插件」，所以这里只拷 app 目录；当前主题仍是 luci-theme-argon，
#   luci.main.mediaurlbase 一个字节都不动，从根上避开那类登录页/外壳问题。
#   上游 README 也写明：dashboard 单独装时在任何主题下都能工作。
#
# 中文：上游自带 po/zh_Hans/vantage.po（3939 行完整简体中文），luci.mk 会据此
#   生成 luci-i18n-vantage-zh-cn（LUCI_LC_ALIAS.zh_Hans=zh-cn）。三份 config
#   里已有 CONFIG_LUCI_LANG_zh_Hans=y + luci-i18n-base-zh-cn=y，中文环境现成。
#
# 依赖已逐个查过底座 pbs05/ponwrt master，全部真实存在（不用降级 hack）：
#   package/system/rpcd/Makefile        → rpcd / rpcd-mod-iwinfo / rpcd-mod-ucode
#   package/utils/ucode/Makefile        → ucode / libucode / ucode-mod-{fs,uci,ubus,rtnl,nl80211}
#   feeds/luci/luci.mk                  → 存在（Makefile include 的就是它）
# ------------------------------------------------------------------------
if [ "$ADD_VANTAGE" = "true" ]; then
  VT_TMP="$(mktemp -d)/vantage"
  # 锁 v1.1.1 tag，不跟 main 漂移；-b <tag> 会进 detached HEAD，结构可复现
  if clone https://github.com/anothaDev/luci-theme-vantage "$VT_TMP" v1.1.1 \
     && [ -f "$VT_TMP/luci-app-vantage/Makefile" ]; then
    # 结构护栏：缺任何一项都说明上游改版，宁可停下也不要编出一个半残的仪表盘
    VT_MK="$VT_TMP/luci-app-vantage/Makefile"
    grep -q 'LUCI_DEPENDS.*rpcd-mod-ucode' "$VT_MK" \
      || { echo "::error::luci-app-vantage Makefile 依赖结构变了，请核对 v1.1.1"; exit 1; }
    [ -f "$VT_TMP/luci-app-vantage/po/zh_Hans/vantage.po" ] \
      || { echo "::error::缺 po/zh_Hans/vantage.po，中文包 luci-i18n-vantage-zh-cn 生成不了"; exit 1; }
    [ -f "$VT_TMP/luci-app-vantage/root/usr/share/luci/menu.d/zz-luci-app-vantage.json" ] \
      || { echo "::error::缺 menu.d 注册文件，admin/dashboard 不会出现"; exit 1; }
    rm -rf "$PKG_DIR/luci-app-vantage" && cp -r "$VT_TMP/luci-app-vantage" "$PKG_DIR/"
    # 再次确认没把主题带进来（双保险）
    # 注意：不能写 `[ -d ... ] && rm -rf ...` —— set -e 下目录不存在时
    # 整个 AND list 返回 1 会把脚本直接打断。无条件 rm 更稳。
    rm -rf "$PKG_DIR/luci-theme-vantage" 2>/dev/null || true
    echo "✅ 已拷贝: luci-app-vantage（含 zh_Hans 中文 po；主题未拷贝）"
  else
    echo "::error::luci-app-vantage 拉取失败或结构变化"
  fi
fi

# --- SmartDNS【本版已移除】-------------------------------------------
# 2026-11-23 用户要求「剔除系统的 dns，只要 passwall」：
#   · configs/*.config 里 smartdns / luci-app-smartdns / 中文包 3 行全改 is not set
#   · files/etc/config/smartdns 与 99-zz-smartdns 已从修复包删除
#   · DNS 由 PassWall 独占（dns_shunt=chinadns-ng + dns_redirect=1），
#     出厂配置由 files/etc/uci-defaults/99-zz-passwall-dns 写入
#   ⚠ dnsmasq-full 保留：LAN DHCP 靠它，PassWall LUCI_DEPENDS 也硬依赖。
#   下面整段不执行（ADD_SMARTDNS=false），保留代码只是留个可逆开关。
if [ "$ADD_SMARTDNS" = "true" ]; then
  echo "::warning::ADD_SMARTDNS 又被打开了 —— config 里 3 行仍是 is not set，=y 不会生效；"
  echo "        确认要恢复 SmartDNS 需同时改 configs/*.config 与 files/"
  rm -rf "package/feeds/luci/luci-app-smartdns" "package/feeds/custom/luci-app-smartdns"
  if ! clone https://github.com/pymumu/luci-app-smartdns "$PKG_DIR/luci-app-smartdns" master; then
    echo "::error::luci-app-smartdns 拉取失败"
    exit 1
  fi
fi

# --- rtp2httpd v3.17.2（RTP/UDP/RTSP → HTTP，FCC 快速换台）----------------
# 上游 stackia/rtp2httpd，OpenWrt 集成包在仓库的 openwrt-support/ 下，两个包：
#   openwrt-support/rtp2httpd/          本体（cmake，源码从 GitHub Release 下载）
#   openwrt-support/luci-app-rtp2httpd/ LuCI 界面 + po/zh_Hans/rtp2httpd.po
#
# ⚠ 必须用 Makefile.versioned 覆盖 Makefile（官方「固件维护者集成指南」）：
#   它固定了 RELEASE_VERSION + PKG_HASH，构建时从
#   https://codeload.github.com/stackia/rtp2httpd/tar.gz/v<版本> 下载源码包，
#   Web UI 已预构建进 tarball —— 不需要 Node / pnpm / corepack，
#   也不需要本地 git 历史。直接用原始 Makefile 会走 PKG_SOURCE_PROTO=git
#   并在编译期联网，350 分钟的 job 里最容易挂。
#
# ⚠ 每次 clone main 当前 HEAD，Makefile.versioned 里的版本随上游 Release
#   自动更新（当前 v3.17.2, 2026-10-02），所以「编译最新」是自动的。
#   想锁版本：把 R2_BRANCH 改成 v3.17.2 之类的 tag。
# ------------------------------------------------------------------------
if [ "$ADD_RTP2HTTPD" = "true" ]; then
  # ------------------------------------------------------------------
  # ★★ 2026-11-23 冲突修复：feeds 里本来就有同名包 ★★
  #   immortalwrt/packages/net/rtp2httpd          → PKG_VERSION 3.16.0
  #   immortalwrt/luci/applications/luci-app-rtp2httpd → 自带 po/zh_Hans
  #   它们经 ./scripts/feeds install -a 后会在 package/feeds/{packages,luci}/
  #   生成符号链接。我们再把上游 openwrt-support/ 拷进 package/custom/，
  #   索引里就是**两份同名 Package**：
  #     · package-metadata 按扫描顺序挑一个 → 可能编出 3.16.0 而不是 3.17.2
  #     · luci-i18n-rtp2httpd-zh-cn 会由两份 po 各生成一次
  #     · LuCI 菜单 / rpcd ACL 重复注册
  #   这正是本文件开头「同名包不能两份同时进索引」警告的情形。
  #   所以拷包前必须把 feeds 的源码目录 + package/feeds 符号链接一起删掉。
  #   （diy-part1.sh 在 feeds update/install 之后执行，删掉不会被重建。）
  # ------------------------------------------------------------------
  for d in feeds/packages/net/rtp2httpd \
           feeds/luci/applications/luci-app-rtp2httpd \
           package/feeds/packages/rtp2httpd \
           package/feeds/luci/luci-app-rtp2httpd \
           package/feeds/custom/rtp2httpd \
           package/feeds/custom/luci-app-rtp2httpd; do
    if [ -e "$d" ] || [ -L "$d" ]; then
      rm -rf "$d"
      echo "ℹ 移除 feeds 同名包: $d"
    fi
  done

  : "${R2_BRANCH:=main}"
  R2_TMP="$(mktemp -d)/rtp2httpd"
  if ! clone https://github.com/stackia/rtp2httpd "$R2_TMP" "$R2_BRANCH"; then
    echo "::error::stackia/rtp2httpd 拉取失败，config 里的 rtp2httpd=y 会被 defconfig 剔除"
    exit 1
  fi
  echo "ℹ rtp2httpd 源: stackia/rtp2httpd @ ${R2_BRANCH}"
  echo "ℹ rtp2httpd 提交: $(git -C "$R2_TMP" rev-parse --short HEAD) · $(git -C "$R2_TMP" log -1 --format='%ci %s')"

  for p in rtp2httpd luci-app-rtp2httpd; do
    SRC="$R2_TMP/openwrt-support/$p"
    if [ ! -f "$SRC/Makefile" ]; then
      echo "::error::openwrt-support/$p/Makefile 不存在（上游改结构了？）"
      exit 1
    fi
    if [ ! -f "$SRC/Makefile.versioned" ]; then
      echo "::error::openwrt-support/$p/Makefile.versioned 不存在，无法固定版本与 PKG_HASH"
      exit 1
    fi
    rm -rf "$PKG_DIR/$p" "package/feeds/custom/$p"
    cp -a "$SRC" "$PKG_DIR/$p"
    mv -f "$PKG_DIR/$p/Makefile.versioned" "$PKG_DIR/$p/Makefile"
    R2_VER="$(grep -m1 '^RELEASE_VERSION:=' "$PKG_DIR/$p/Makefile" | sed 's/.*:=//')"
    echo "✅ 已拷入: package/custom/$p (RELEASE_VERSION=${R2_VER:-?}, Makefile.versioned → Makefile)"
  done
  # 中文包由 luci.mk 按 po/zh_Hans/rtp2httpd.po 生成 luci-i18n-rtp2httpd-zh-cn
  [ -f "$PKG_DIR/luci-app-rtp2httpd/po/zh_Hans/rtp2httpd.po" ] \
    || echo "::warning::缺 po/zh_Hans/rtp2httpd.po，中文包可能不生成"
  rm -rf "$R2_TMP"

  # 自检：确认全树只剩我们拷的这一份，且版本是上游最新
  DUP=""
  for d in feeds/packages/net/rtp2httpd \
           feeds/luci/applications/luci-app-rtp2httpd \
           package/feeds/packages/rtp2httpd \
           package/feeds/luci/luci-app-rtp2httpd; do
    if [ -e "$d" ] || [ -L "$d" ]; then DUP="$DUP $d"; fi
  done
  if [ -n "$DUP" ]; then
    echo "::error::rtp2httpd 同名包仍存在（会双份进索引）:$DUP"
    exit 1
  fi
  R2_VER="$(grep -m1 '^RELEASE_VERSION:=' "$PKG_DIR/rtp2httpd/Makefile" | sed 's/.*:=//')"
  echo "✅ rtp2httpd 索引唯一：package/custom/{rtp2httpd,luci-app-rtp2httpd} @ v${R2_VER:-?}（feeds 同名包已清）"
fi

# --- fastnet（LinEase / iStoreOS 生态）---------------------------------
# luci-app-fastnet 的 LUCI_DEPENDS := +fastnet +luci-lib-linkeaseauth
#                                   +linkease-app-entry
# 四个包分属两个仓库，缺一个 defconfig 就会把 =y 静默剔除：
#   linkease/nas-packages         network/services/{fastnet,linkease-app-entry}
#   linkease/nas-packages-luci    luci/{luci-app-fastnet,luci-lib-linkeaseauth}
# fastnet 本体是预编译二进制（从 istoreos-app-hub Releases 下载），
# DEPENDS := @(arm||x86_64||aarch64) +linkease-app-entry；AN758x 为 aarch64，满足。
# linkease-app-entry 再依赖 ca-bundle + luci-lib-linkeaseauth，均在 feeds/本段内。
# ------------------------------------------------------------------------
if [ "$ADD_FASTNET" = "true" ]; then
  NAS_TMP="$(mktemp -d)/nas-packages"
  LUCI_TMP="$(mktemp -d)/nas-packages-luci"
  if clone https://github.com/linkease/nas-packages "$NAS_TMP" master \
     && clone https://github.com/linkease/nas-packages-luci "$LUCI_TMP" main; then
    for p in fastnet linkease-app-entry; do
      if [ -f "$NAS_TMP/network/services/$p/Makefile" ]; then
        rm -rf "$PKG_DIR/$p" && cp -r "$NAS_TMP/network/services/$p" "$PKG_DIR/"
        echo "✅ 已拷贝: $p"
      else
        echo "::error::nas-packages 里缺 network/services/$p（fastnet 依赖链断）"
      fi
    done
    for p in luci-app-fastnet luci-lib-linkeaseauth; do
      if [ -f "$LUCI_TMP/luci/$p/Makefile" ]; then
        rm -rf "$PKG_DIR/$p" && cp -r "$LUCI_TMP/luci/$p" "$PKG_DIR/"
        echo "✅ 已拷贝: $p"
      else
        echo "::error::nas-packages-luci 里缺 luci/$p（fastnet 依赖链断）"
      fi
    done
  else
    echo "::error::fastnet 依赖仓库拉取失败（不影响其余插件）"
  fi
fi
# --- luci-theme-fluent ---
# ⚠ 包在仓库的 package/ 子目录下，不能直接 clone 到 package/custom，
#   必须把子目录拷出来，否则 buildroot 扫不到 Makefile
if [ "$ADD_FLUENT" = "true" ] || [ "$ADD_FLUENT_LITE" = "true" ] || [ "$ADD_FLUENT_DASH" = "true" ]; then
  FLUENT_TMP="$(mktemp -d)/fluent"
  clone https://github.com/LazuliKao/luci-theme-fluent "$FLUENT_TMP" main

  for p in luci-theme-fluent luci-theme-fluent-lite luci-mod-fluentdashboard; do
    case "$p" in
      luci-theme-fluent)        [ "$ADD_FLUENT" = "true" ] || continue ;;
      luci-theme-fluent-lite)   [ "$ADD_FLUENT_LITE" = "true" ] || continue ;;
      luci-mod-fluentdashboard) [ "$ADD_FLUENT_DASH" = "true" ] || continue ;;
    esac
    [ -d "$FLUENT_TMP/package/$p" ] || { echo "::error::$p 不存在"; continue; }
    rm -rf "$PKG_DIR/$p"
    cp -a "$FLUENT_TMP/package/$p" "$PKG_DIR/$p"
    echo "✅ 已拷贝: $p"
  done
  rm -rf "$FLUENT_TMP"
fi

if [ "$ADD_EASYTIER" = "true" ]; then
  clone https://github.com/EasyTier/luci-app-easytier "$PKG_DIR/luci-app-easytier" main
fi
if [ "$ADD_POWEROFF" = "true" ]; then
  clone https://github.com/sirpdboy/luci-app-poweroffdevice "$PKG_DIR/luci-app-poweroffdevice" master
fi
if [ "$ADD_OWQ_WOL" = "true" ]; then
  clone https://github.com/isalikai/luci-app-owq-wol "$PKG_DIR/luci-app-owq-wol" main
fi
if [ "$ADD_TASKPLAN" = "true" ]; then
  clone https://github.com/sirpdboy/luci-app-taskplan "$PKG_DIR/luci-app-taskplan" main
fi

# ---------------------------------------------------------------------
# ★ 2026-11-23 编译失败根治（run 45098102616，耗时 1h48m 后挂）
#
#   真错误：2736:./etc/init.d/taskplan: line 14:
#           /etc/taskplan/taskplan.log: No such file or directory
#   连锁：make[2] package/install Error 1 → make[1] .package_install Error 2
#         → make world Error 2。
#
#   根因：上游 sirpdboy/luci-app-taskplan@main 新版（"Converted for OpenWrt
#   25.10", PKG_RELEASE 20260303）在 init.d 脚本**顶层**新增了三行：
#       # 确保目录存在
#       [ ! -d $TMP ] && mkdir -p $TMP 2>/dev/null
#       [ ! -s $LOG ] && echo '' > $LOG
#   PonWrt 用 apk，package/install 装配 rootfs 时会在 INSTROOT 环境里以
#   普通 sh 执行包内 ./etc/init.d/taskplan 的顶层（shebang 的
#   /etc/rc.common 在此环境不存在，被当注释忽略）。此时 $TMP=/etc/taskplan
#   指向构建主机的 /etc，runner 用户无权创建 → mkdir 失败被 2>/dev/null
#   吞掉 → echo > /etc/taskplan/taskplan.log 报 No such file → 脚本非 0
#   退出 → postinst 失败。
#
#   修法：顶层不再写任何绝对路径；目录/日志初始化移到运行时函数
#   run_taskplan() / del_cru() 开头（uci-defaults 也会 mkdir -p 兜底），
#   并全部用 `|| :` 保证永不因写文件失败而返回非 0。
#   uci-defaults 里 chmod 一个运行时才生成的文件同样改成容错。
#
#   为什么每次都要打：仓库按用户要求 --depth 1 拉 main 最新，不锁 commit，
#   上游下次改结构时本补丁按内容匹配、不按行号，找不到就明确报错早退，
#   不会静默编到 1h48m 才炸。
# ---------------------------------------------------------------------
if [ "$ADD_TASKPLAN" = "true" ]; then
  TP_DIR="$PKG_DIR/luci-app-taskplan"
  TP_INIT="$(find "$TP_DIR" -path '*/root/etc/init.d/taskplan' -type f 2>/dev/null | head -1)"
  TP_UCI="$(find "$TP_DIR" -path '*/root/etc/uci-defaults/luci-taskplan' -type f 2>/dev/null | head -1)"

  if [ -z "$TP_INIT" ] || [ ! -f "$TP_INIT" ]; then
    echo "::error::taskplan 的 init.d 没找到（上游改了目录结构？）。本补丁是编译必需项，不能静默跳过：package/install 会在约 1.5 小时后因 init.d 顶层写 /etc 失败。"
    exit 1
  fi

  python3 - "$TP_INIT" "${TP_UCI:-}" <<'PYFIX'
import sys, io
p = sys.argv[1]
u = sys.argv[2] if len(sys.argv) > 2 else ''
s = io.open(p, encoding='utf-8').read()
orig_lines = s.splitlines()

# 1) 移除顶层三行「确保目录存在」（按内容匹配，上游换行/缩进变化也能命中）
lines = [l for l in s.splitlines(True)
         if not (l.strip() == '# 确保目录存在'
                 or '[ ! -d $TMP ] && mkdir -p $TMP' in l
                 or "[ ! -s $LOG ] && echo '' > $LOG" in l)]
removed = len(s.splitlines(True)) - len(lines)
s = ''.join(lines)

# 2) 在 run_taskplan() / del_cru() 的 '{' 之后插入幂等初始化
init = ('    mkdir -p "$TMP" 2>/dev/null || :\n'
        '    [ -d "$TMP" ] && : > "$LOG" 2>/dev/null || :\n')
out, i, inserted = [], 0, 0
while i < len(s.splitlines(True)):
    L = s.splitlines(True)
    out.append(L[i])
    if L[i].strip() in ('run_taskplan()', 'del_cru()'):
        j = i + 1
        while j < len(L) and L[j].strip() != '{':
            out.append(L[j]); j += 1
        if j < len(L):
            out.append(L[j]); out.append(init); inserted += 1
            i = j + 1
            continue
    i += 1
s = ''.join(out)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('  ✅ init.d/taskplan: 顶层移除 %d 行，运行时初始化插入 %d 处' % (removed, inserted))

# 3) uci-defaults 里 /etc/taskplan/taskplanrun 打包时不存在 → chmod 容错
if u:
    t = io.open(u, encoding='utf-8').read()
    old = ('chmod +x /usr/libexec/rpcd/luci.taskplan /etc/init.d/taskplan '
           '/etc/taskplan/taskplanrun /usr/bin/taskplanhandler')
    new = ('chmod +x /usr/libexec/rpcd/luci.taskplan /etc/init.d/taskplan '
           '/usr/bin/taskplanhandler 2>/dev/null || :\n'
           '[ -f /etc/taskplan/taskplanrun ] && chmod +x /etc/taskplan/taskplanrun 2>/dev/null || :')
    if old in t:
        io.open(u, 'w', encoding='utf-8', newline='\n').write(t.replace(old, new, 1))
        print('  ✅ uci-defaults/luci-taskplan: chmod 已容错')
PYFIX

  # 编译前硬校验：只按内容精确匹配「原始顶层两行」。
  # 不能 head -20 粗扫 —— 补丁把 mkdir -p "$TMP" 插到了 run_taskplan() 里
  # （约第 15 行），粗扫会把我们自己插入的初始化误判成未修复。
  # 早退在 diy 阶段（几分钟），不要等 1h48m 才在 package/install 炸。
  if grep -qE '^\[ ! -d \$TMP \] && mkdir -p \$TMP|^\[ ! -s \$LOG \] && echo .. > \$LOG' "$TP_INIT"; then
    echo "::error::taskplan init.d 顶层仍会写 /etc/taskplan（补丁未生效），package/install 必然失败"
    exit 1
  fi
  echo "✅ taskplan 编译期 postinst 修复完成：顶层不写 /etc，初始化移到运行时函数"
fi
# --- watchdog ---
# ⚠ 仓库是 monorepo：根目录无 Makefile，luci-app-watchdog/（前端）与
#   watchdog/（本体）是两个包，前者依赖 +watchdog，两个都要拷。
#   只拷前端时索引会报 "has a dependency on 'watchdog', which does not exist"。
if [ "$ADD_WATCHDOG" = "true" ]; then
  WD_TMP="$(mktemp -d)/wd"
  if clone https://github.com/sirpdboy/luci-app-watchdog "$WD_TMP" main; then
    for p in luci-app-watchdog watchdog; do
      [ -f "$WD_TMP/$p/Makefile" ] || { echo "::warning::$p 不存在（上游改结构了？）"; continue; }
      rm -rf "$PKG_DIR/$p"
      cp -r "$WD_TMP/$p" "$PKG_DIR/"
      echo "✅ 已拷贝: $p"
    done
  else
    echo "::error::luci-app-watchdog 拉取失败"
  fi
  rm -rf "$WD_TMP"
fi
if [ "$ADD_OAF" = "true" ]; then
  # 三个子目录的真实包名（已逐个读 Makefile 核实，别按目录名猜）：
  #   luci-app-oaf/        → PKG_NAME:=luci-app-oaf   LUCI_DEPENDS:=+appfilter +kmod-oaf +luci-compat +luci-lib-jsonc
  #   open-app-filter/     → PKG_NAME:=appfilter      （OAF 用户态服务）
  #   oaf/                 → KernelPackage oaf        → 索引名 kmod-oaf（外部内核模块）
  # ⚠ 本版已按用户要求整组移除（ADD_OAF=false，下面这段不会执行）：
  #   kmod-oaf 是 obj-m 外部模块（netfilter hook），上游主要跟 5.4/5.15，
  #   本机 Linux 6.18 大概率 API 不兼容。保留代码只为留档，不 clone、不进索引。
  clone https://github.com/destan19/OpenAppFilter "$PKG_DIR/OpenAppFilter" master
  for p in luci-app-oaf open-app-filter oaf; do
    [ -f "$PKG_DIR/OpenAppFilter/$p/Makefile" ] \
      || { echo "::warning::OpenAppFilter 缺子目录 $p（上游改结构了？）"; continue; }
    rm -rf "$PKG_DIR/$p" && cp -r "$PKG_DIR/OpenAppFilter/$p" "$PKG_DIR/"
    echo "✅ 已拷贝: $p"
  done
  # 确认前端声明的依赖与我们的目录对得上
  grep -q 'LUCI_DEPENDS.*appfilter.*kmod-oaf' "$PKG_DIR/luci-app-oaf/Makefile" \
    || echo "::warning::luci-app-oaf 依赖结构变了，请核对"
  rm -rf "$PKG_DIR/OpenAppFilter"
fi
# --- ttyd / luci-app-ttyd（网页终端）--------------------------------------
# 官方 feeds 自带，不需要 clone：
#   immortalwrt/packages  utils/ttyd/Makefile          → 包 ttyd
#   immortalwrt/luci      applications/luci-app-ttyd  → LUCI_DEPENDS:=+luci-base +ttyd
#                                                     po/zh_Hans/ttyd.po → luci-i18n-ttyd-zh-cn
# 所以这里只打印一行说明，真正的开关在 configs/*.config 里的 =y。
# ------------------------------------------------------------------------
if [ "$ADD_TTYD" = "true" ]; then
  echo "✅ ttyd / luci-app-ttyd 走官方 feeds，只写 config（无 clone）"
fi

# --- 上网时间控制：luci-app-accesscontrol-plus -----------------------------
# ⚠ 关于你点名的 `luci-app-accesscontrol`（无连字符）：
#   那是 2016 年 fw3/iptables 时代的老包（Makefile: PKG_VERSION:=1 /
#   PKG_RELEASE:=11 / LUCI_DEPENDS 为空，直接调 iptables 写规则，无中文 po）。
#   这套固件是 Linux 6.18 + firewall4(nftables)，OpenWrt 22.03 起自定义
#   iptables 规则需改用 nft 机制，老包装上去菜单在、规则不生效。
#   常见第三方源（coolsnowwolf/lede、sirpdboy-package、kiddin9、kenzok8）
#   现在也都已把它移除/改名，raw 直连全是 404。
#
#   因此改用同源的增强版 `luci-app-accesscontrol-plus`（kingyond 原作）：
#   README 明确写了 fw4 下用 nft `meta hour/day`、DNS 53 拦截、时区/DST
#   注意事项，正是「按 MAC + 时段 + 星期控制上网 + 临时放行票」那个功能。
#   中文 po 在 po/zh-Hans/miaplus.po —— 目录名是连字符，luci.mk 的
#   LUCI_LANG 只认 zh_Hans（下划线），所以下面要重命名一次，
#   才能生成 luci-i18n-accesscontrol-plus-zh-cn。
#
#   另一个坑：上游 Makefile 写 LUCI_DEPENDS:=+snmpd，但 immortalwrt/packages
#   net/net-snmp 里定义的包是 snmpd-nossl / snmpd-ssl，没有裸 snmpd，
#   defconfig 会因此把整个 app 静默剔除。下面改成 +snmpd-nossl。
# ------------------------------------------------------------------------
if [ "$ADD_ACCESSCONTROL" = "true" ]; then
  AC_TMP="$(mktemp -d)/ac"
  if clone https://github.com/kingyond/luci-app-accesscontrol-plus "$AC_TMP" main \
     && [ -f "$AC_TMP/luci-app-accesscontrol-plus/Makefile" ]; then
    AC_SRC="$AC_TMP/luci-app-accesscontrol-plus"
    grep -q 'PKG_NAME:=luci-app-accesscontrol-plus' "$AC_SRC/Makefile" \
      || { echo "::error::accesscontrol-plus Makefile 结构变了"; exit 1; }
    # 中文目录：zh-Hans → zh_Hans（luci.mk 只认下划线）
    if [ -d "$AC_SRC/po/zh-Hans" ] && [ ! -d "$AC_SRC/po/zh_Hans" ]; then
      mv "$AC_SRC/po/zh-Hans" "$AC_SRC/po/zh_Hans"
      echo "✅ 中文目录已规范: po/zh-Hans → po/zh_Hans"
    fi
    # 依赖名：snmpd → snmpd-nossl（底座实际提供的包名）
    sed -i 's/^LUCI_DEPENDS:=+snmpd$/LUCI_DEPENDS:=+snmpd-nossl/' "$AC_SRC/Makefile"
    grep -q 'LUCI_DEPENDS:=+snmpd-nossl' "$AC_SRC/Makefile" \
      || { echo "::error::accesscontrol-plus 依赖改写失败"; exit 1; }
    rm -rf "$PKG_DIR/luci-app-accesscontrol-plus"
    cp -r "$AC_SRC" "$PKG_DIR/"
    echo "✅ 已拷贝: luci-app-accesscontrol-plus（fw4 版上网时间控制，含中文）"
  else
    echo "::error::luci-app-accesscontrol-plus 拉取失败或结构变化"
  fi
  rm -rf "$AC_TMP"
fi

# 原版 luci-app-accesscontrol：默认关。真要编（预期 fw4 下不生效）就把
# ADD_ACCESSCONTROL_LEGACY 改 true，并自行补一个可信源；这里不自动 clone，
# 避免拉到 404 仓库把整轮编译拖死。
if [ "$ADD_ACCESSCONTROL_LEGACY" = "true" ]; then
  echo "::warning::ADD_ACCESSCONTROL_LEGACY=true：原版是 fw3/iptables 包，fw4 下预计不生效"
fi

# ---------------------------------------------------------
# 校验：默认开启的两个插件必须拉到，否则 defconfig 会静默剔除，
#       编出来的固件缺少状态页还不易察觉
# ---------------------------------------------------------
if [ "$ADD_AIROHA_NPU" = "true" ] && [ ! -d "$PKG_DIR/luci-app-airoha-npu" ]; then
  echo "::error::luci-app-airoha-npu 未拉到，config 里的 =y 会被 defconfig 剔除"
  exit 1
fi
# natmode / pon-status 来自 qwe3017/luci-app（config 里也是 =y）
for p in luci-app-natmode luci-app-pon-status luci-app-igmpproxy; do
  if [ "$ADD_LUCI_APP" = "true" ] && [ ! -d "$PKG_DIR/$p" ]; then
    echo "::error::$p 未拉到，config 里的 =y 会被 defconfig 剔除"
    exit 1
  fi
done
# ---------------------------------------------------------
# 补回 libffi —— python3(3.14) 的 _ctypes 硬性需要
#   CPython 自 3.11 起删掉了 --with-system-ffi，_ctypes 永远 #include <ffi.h>；
#   而 ponwrt 与 immortalwrt/packages 的 libffi 目录都已不存在，整棵树里没有
#   ffi.h / libffi.pc，于是编到 _ctypes.c 才炸：
#     ./Modules/_ctypes/_ctypes.c:119:10: fatal error: ffi.h: No such file...
#   处理：从 immortalwrt 基座取现成的包定义（自带 Build/InstallDev，会把
#   ffi.h / libffi.pc 装进 staging_dir），再给 python3 补一条构建依赖。
# ⚠ 必须放在 prepare-tmpinfo 之前：目录要被扫进索引，PKG_BUILD_DEPENDS 也要生效。
# ---------------------------------------------------------
FFI_DIR="package/custom/libffi"
if [ ! -d "$FFI_DIR" ]; then
  echo "--- 补回 libffi（python3 _ctypes 依赖，源码树中缺失）---"
  mkdir -p "$FFI_DIR"
  if curl -fsSL --retry 3 --max-time 60 \
       https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/package/libs/libffi/Makefile \
       -o "$FFI_DIR/Makefile"; then
    echo "✅ 已补回 libffi ($(grep -m1 '^PKG_VERSION' "$FFI_DIR/Makefile" 2>/dev/null))"
  else
    echo "::error::libffi 包定义下载失败 —— python3 的 _ctypes 会因缺 ffi.h 编译失败"
    rm -rf "$FFI_DIR"
  fi
else
  echo "已存在，跳过: $FFI_DIR"
fi

# python3 只声明了 libffi/host，target 侧没声明，补一条确保 libffi 先编译
PY3MK="feeds/packages/lang/python/python3/Makefile"
if [ -f "$PY3MK" ] && ! grep -q 'PKG_BUILD_DEPENDS:=bluez libffi' "$PY3MK"; then
  sed -i 's|^PKG_BUILD_DEPENDS:=bluez|PKG_BUILD_DEPENDS:=bluez libffi|' "$PY3MK"
  echo "✅ python3 已补 libffi 构建依赖（PKG_BUILD_DEPENDS，保证先编 libffi）"
fi

# ---------------------------------------------------------
# 清理重复嵌套目录
# rchen14b/luci-app-airoha-npu 这个仓库有问题：包在根目录放了一份，
# 又在同名子目录 luci-app-airoha-npu/ 里放了完整一份（含 Makefile）。
# feeds 扫描会把两层都当成独立包，内层 dump 失败（报
# "feeds/custom/luci-app-airoha-npu/luci-app-airoha-npu"）会中断整个
# custom feed 的索引，导致 package/feeds/custom 压根不生成，
# 所有包符号都不存在。
# ---------------------------------------------------------
echo "--- 检查重复嵌套目录 ---"
# ⚠ 判据必须包含「根目录也有 Makefile」，否则会误删 monorepo 的真包：
#   lucky / openlist2 / easytier / taskplan / poweroffdevice 的仓库根目录【没有】
#   Makefile，同名子目录才是唯一的那份包 —— 只看「有同名子目录」就会把它们
#   当重复项删掉，包从索引里消失、config 的 =y 被 defconfig 静默剔除。
#   只有 rchen14b/luci-app-airoha-npu 那种「根目录一份 + 同名子目录又一份」
#   才是要清理的坏结构（内层 dump 失败会中断整个 custom feed 的索引）。
for d in "$PKG_DIR"/*; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if [ -f "$d/Makefile" ] && [ -d "$d/$n" ] && [ -f "$d/$n/Makefile" ]; then
    rm -rf "$d/$n"
    echo "✅ 已移除重复嵌套目录: $n/$n"
  fi
done
# ---------------------------------------------------------
# 让新包进入索引
#   ⚠ 判据是 tmp/.packageinfo，不是 package/feeds/custom
#   prepare-tmpinfo 直接扫 package/ 树（scan.mk: find -L package -maxdepth 5），
#   package/custom/<pkg>/Makefile 深度 3，本来就会被扫到，**不需要注册 feed**。
#   旧的 src-link custom feed 有两个坑：① 同一批 Makefile 被扫两遍，按 Override
#   挑一个、行为随扫描顺序漂移；② install_src() 看到 $installed 非空直接 return，
#   压根不建 package/feeds/custom/<pkg> —— 所以它不存在是正常的，拿它当判据必然误报。
# ---------------------------------------------------------
if [ -n "$(ls -A "$PKG_DIR" 2>/dev/null)" ]; then
  # =========================================================
  # 强制重建索引
  #   只删 tmp/.packageinfo 是不够的：prepare-tmpinfo 有 scan_unchanged
  #   优化（拿 tmp/info/.scan-*.stamp 比 mtime），stamp 还在且没有更新的
  #   Makefile 时它会跳过扫描 —— 结果 .packageinfo 被删了却没人重建，
  #   索引反而空了。所以 stamp 也要一起删。
  # =========================================================
  rm -f tmp/.packageinfo tmp/.targetinfo
  rm -f tmp/info/.scan-packageinfo.stamp tmp/info/.scan-targetinfo.stamp
  rm -f tmp/.config-package.in tmp/.config-target.in
  echo ">>> make prepare-tmpinfo（重新扫描 package/ 树）"
  make -s prepare-tmpinfo OPENWRT_BUILD= 2>&1 | tail -5 || true
  echo "=========================================="
  echo "包索引校验（判据：tmp/.packageinfo）"
  echo "=========================================="
  echo "package/custom 内容："
  INDEX_MISS=""
  # 目录名 ≠ 包名的情况（Makefile 里显式写了 PKG_NAME / KernelPackage）：
  #   open-app-filter 的包是 appfilter、oaf 的 KernelPackage 是 kmod-oaf，
  #   按目录名去索引里查必然查不到 —— 那是误报，不是索引失败。
  pkgname_of() {
    case "$1" in
      open-app-filter) echo "appfilter" ;;
      oaf)             echo "kmod-oaf" ;;
      h3c-fmcs)        echo "kmod-h3c-fmcs" ;;
      # naoki66/OpenWrt_ONU_CONFIG 的目录叫 airoha-pon-daemons，
      # 但 Makefile 里 PKG_NAME 同名、define Package/airoha-pond —— 索引里是
      # airoha-pond。run #23 日志里「❌ airoha-pon-daemons 查不到」是误报，
      # 实际 airoha-pond=y 已编入、PON 关键包校验也通过了。
      airoha-pon-daemons) echo "airoha-pond" ;;
      *)               echo "$1" ;;
    esac
  }

  for d in "$PKG_DIR"/*; do
    [ -d "$d" ] || continue
    n=$(basename "$d")

    # 无根 Makefile = monorepo 容器（lucky / openlist2 / easytier / taskplan /
    # poweroffdevice / watchdog），真正的包在同名子目录里，逐个查
    if [ ! -f "$d/Makefile" ]; then
      found=0
      # 直接对 glob 迭代，不拼字符串再分词 —— 拼了就得依赖 IFS 分词，
      # 换个 shell（zsh 默认不拆）行为就变
      for sd in "$d"/*/Makefile; do
        [ -f "$sd" ] || continue
        found=1
        sn="$(basename "$(dirname "$sd")")"
        if grep -qx "Package: $sn" tmp/.packageinfo 2>/dev/null; then
          echo "  ✅ $n → $sn"
        else
          echo "  ❌ $n → $sn —— tmp/.packageinfo 里查不到"
          INDEX_MISS="$INDEX_MISS $sn"
          for f in "logs/package/$sn/dump.txt" "logs/package/custom/$sn/dump.txt"; do
            [ -f "$f" ] && { echo "===== $f ====="; tail -25 "$f"; }
          done
        fi
      done
      [ "$found" = 1 ] || echo "  -  $n（无 Makefile，跳过）"
      continue
    fi

    pn="$(pkgname_of "$n")"
    if grep -qx "Package: $pn" tmp/.packageinfo 2>/dev/null; then
      echo "  ✅ $n${pn:+$([ "$pn" != "$n" ] && echo " → $pn")}"
    else
      echo "  ❌ $n（包名 $pn）—— tmp/.packageinfo 里查不到"
      INDEX_MISS="$INDEX_MISS $pn"
      # 真实错误在这里（scan.mk 落盘路径 logs/<SCAN_DIR>/<相对目录>/dump.txt）
      for f in "logs/package/$n/dump.txt" "logs/package/custom/$n/dump.txt"; do
        [ -f "$f" ] && { echo "===== $f ====="; tail -25 "$f"; }
      done
    fi
  done
  echo "------------------------------------------"
  echo "luci.mk: $([ -f feeds/luci/luci.mk ] && echo '✓' || echo '✗ 缺失（luci app 无法解析）')"
  echo "tmp/.packageinfo 包总数: $(grep -c '^Package: ' tmp/.packageinfo 2>/dev/null || echo 0)"
  echo "=========================================="
  # 必装插件（config 里是 =y 的那几个）必须进索引，否则 defconfig 会静默剔除
  REQUIRED=""
  [ "$ADD_AIROHA_NPU" = "true" ] && REQUIRED="$REQUIRED luci-app-airoha-npu"
  if [ "$ADD_LUCI_APP" = "true" ]; then
    # 用户复核：组播双代理都保留，igmpproxy 一并校验索引（拷包失败要在这里报出来）
    REQUIRED="$REQUIRED luci-app-natmode luci-app-pon-status luci-app-igmpproxy"
  fi
  [ "$ADD_ONU" = "true" ] && REQUIRED="$REQUIRED luci-app-onu"
  # naoki66/luci-app-airoha feed：只校验有实体目录的包本体；中文包由 luci.mk 按 po 动态生成
  [ -n "$AIROHA_PKGS" ] && REQUIRED="$REQUIRED $AIROHA_PKGS"
  [ "$ADD_RTP2HTTPD" = "true" ] && REQUIRED="$REQUIRED rtp2httpd luci-app-rtp2httpd"
  [ "$ADD_ISTORE" = "true" ] && REQUIRED="$REQUIRED luci-app-store luci-lib-taskd luci-lib-xterm taskd"

  # 与 configs/an7581.config / an7583.config 里 =y 的包一一对应。
  # 任一项没进索引，defconfig 都会把那个 =y 静默剔除 —— 编出来的固件少了菜单
  # 还不易察觉。所以这里和 config 必须同步改。
  [ "$ADD_FLUENT"    = "true" ] && REQUIRED="$REQUIRED luci-theme-fluent"
  [ "$ADD_OPENCLASH" = "true" ] && REQUIRED="$REQUIRED luci-app-openclash"
  [ "$ADD_PASSWALL"  = "true" ] && REQUIRED="$REQUIRED luci-app-passwall"
  [ "$ADD_MOSDNS"    = "true" ] && REQUIRED="$REQUIRED luci-app-mosdns"
  # ADD_LUCKY 已置 false；DDNS 只留花生壳，无对应实体包需要校验
  [ "$ADD_TAILSCALE" = "true" ] && REQUIRED="$REQUIRED luci-app-tailscale"
  [ "$ADD_OPENLIST"  = "true" ] && REQUIRED="$REQUIRED luci-app-openlist2"
  # ADD_SMARTDNS 已置 false；DNS 改由 PassWall 独占，无对应实体包需要校验
  # 定制增强：fastnet 四个包必须都进索引，否则 defconfig 会静默剔除 =y
  [ "$ADD_FASTNET"   = "true" ] && REQUIRED="$REQUIRED fastnet luci-app-fastnet linkease-app-entry luci-lib-linkeaseauth"
  # ★ 插件去重：Homebox / OpenClash / MosDNS / Tailscale / EasyTier / Fluent
  #   均已 ADD_*=false 且 config 无 =y，下面这些条件式校验自然跳过。
  #   保留条件式是为了「三处一起改回」时能自动恢复，不用再补一行。
  # 定制增强：只校验 app 本体；中文包 luci-i18n-vantage-zh-cn 由 luci.mk 按 po 动态生成，
  # 不在 package 目录里以独立目录出现，放进这里会误报「未进索引」。
  [ "$ADD_VANTAGE"   = "true" ] && REQUIRED="$REQUIRED luci-app-vantage"
  # 本轮 6 个新插件：只校验「有实体目录」的包本体；中文包由 luci.mk 动态生成，
  # 放进来会误报「未进索引」。kmod-oaf / snmpd-nossl / bash / ttyd 是 feed 自带，
  # 也不进 REQUIRED（靠 config 的 =y + workflow 自检兜底）。
  # （同上）Lucky 整组移除
  [ "$ADD_WATCHDOG"       = "true" ] && REQUIRED="$REQUIRED luci-app-watchdog watchdog"
  [ "$ADD_TASKPLAN"       = "true" ] && REQUIRED="$REQUIRED luci-app-taskplan"
  # OAF 已按用户要求移除：整组不 clone、不进 REQUIRED、不写 config
  [ "$ADD_ACCESSCONTROL"  = "true" ] && REQUIRED="$REQUIRED luci-app-accesscontrol-plus"
  [ "$ADD_TTYD"           = "true" ] && REQUIRED="$REQUIRED luci-app-ttyd"
  [ "$ADD_EASYTIER"  = "true" ] && REQUIRED="$REQUIRED luci-app-easytier"
  [ "$ADD_POWEROFF"  = "true" ] && REQUIRED="$REQUIRED luci-app-poweroffdevice"
  [ "$ADD_OWQ_WOL"   = "true" ] && REQUIRED="$REQUIRED luci-app-owq-wol"
  [ "$ADD_WATCHDOG"  = "true" ] && REQUIRED="$REQUIRED luci-app-watchdog"
  [ "$ADD_TASKPLAN"  = "true" ] && REQUIRED="$REQUIRED luci-app-taskplan"
  # （旧 OAF 校验行已随移除一并删掉）
  true
  if [ "$ADD_FTTR" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ]; then
    # KernelPackage 生成的包名带 kmod- 前缀，索引里写的是 kmod-h3c-fmcs
    if [ "$ADD_FMCS" = "true" ]; then
      REQUIRED="$REQUIRED kmod-h3c-fmcs"
    fi
    if [ "$ADD_FMCS_FW" = "true" ]; then
      REQUIRED="$REQUIRED h3c-fmcs-firmware"
    fi
    if [ "$ADD_FTTR_TOOLS" = "true" ]; then
      REQUIRED="$REQUIRED h3c-fttr-tools"
    fi
    REQUIRED="$REQUIRED luci-app-fttr"
    # =========================================================
    # luci-app-fttr 依赖 +h3c-fttr-tools，后者依赖 +kmod-h3c-fmcs。
    # 链条上任一节不在树里，defconfig 都会静默把整条 FTTR 剔掉 —— 与其编出
    # 一个没有 FTTR 界面的固件还不易察觉，不如在这里直接报错。
    # 前者最常见原因是缺 rust-package.mk；后者受 @(TARGET_airoha_an7581) 限制。
    # =========================================================
    if [ "$ADD_FTTR_TOOLS" = "true" ] &&
       ! grep -qx "Package: h3c-fttr-tools" tmp/.packageinfo 2>/dev/null; then
      echo "::error::h3c-fttr-tools 不在包索引里（luci-app-fttr 的后端，Rust 包）"
      echo "        多半是缺 rust feed：确认 feeds.conf 里有 packages，且"
      echo "        ./scripts/feeds install 装到了 lang/rust。"
      echo "        不需要 FTTR 就把 diy-part1.sh 的 ADD_FTTR 改成 false。"
      exit 1
    fi
    if [ "$ADD_FMCS" = "true" ] &&
       ! grep -qx "Package: kmod-h3c-fmcs" tmp/.packageinfo 2>/dev/null; then
      echo "::error::kmod-h3c-fmcs 不在包索引里（h3c-fttr-tools 依赖它）"
      echo "        DEPENDS 是 @(TARGET_airoha_an7581)：非该 target 时包不会进索引。"
      echo "        不需要 FTTR 就把 diy-part1.sh 的 ADD_FTTR 改成 false。"
      exit 1
    fi
  fi
  HARD_MISS=""
  for r in $REQUIRED; do
    grep -qx "Package: $r" tmp/.packageinfo 2>/dev/null || HARD_MISS="$HARD_MISS $r"
  done
  if [ -n "$HARD_MISS" ]; then
    echo "::error::以下必装插件未进入 tmp/.packageinfo，defconfig 会把 .config 里的 =y 静默剔除:$HARD_MISS"
    echo "  已索引缺失清单:$INDEX_MISS"
    exit 1
  fi
  [ -n "$INDEX_MISS" ] && echo "::warning::部分可选包未进入索引（不影响必装插件）:$INDEX_MISS"
else
  echo "未启用任何第三方插件"
fi
echo "🎉 diy-part1.sh 执行完毕"
