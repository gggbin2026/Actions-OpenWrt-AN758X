# PonWrt CI — Airoha AN758x PON 云编译

基于 P3TERX `Actions-OpenWrt` 模板重构，源码指向 [pbs05/ponwrt](https://github.com/pbs05/ponwrt)（默认分支 `master`）。
产出 Airoha AN758x PON 光猫的 OpenWrt 固件，带机型选择、磁盘释放和滚动构建缓存。

> ## 当前状态（2026-11-23，自用 fork 定制版）
>
> **只维护两个机型**：`fiberhome_hg5585f-ct`（272 个包）/ `nokia_xg-040g-md-ubi`（262 个包）。
> `profile=all` 与其余 `configs/*.config` 是上游遗留、**未同步定制**，已停用。
>
> | 项目 | 当前实现 |
> |---|---|
> | 光猫管理 | 只用 `luci-app-onu`（LOID / 认证 / IPTV / 语音 / 诊断）；Airoha feed 四页面与旧 PON 栈已移除 |
> | 组播 | `omcproxy` + `igmpproxy` / `luci-app-igmpproxy` **双代理并存** + `rtp2httpd` v3.17.2；**IGMP Snooping 首启自动开启** |
> | DNS | **PassWall 独占**
> **DHCP Snooping 默认开启**：`files/etc/rogue-dhcp.nft` 在 br-lan 桥层丢弃私设 DHCP 的 OFFER/ACK（含有线 LAN 与 WiFi 桥端口），本机 dnsmasq 不受影响，无需配置。核对 `nft list table bridge rogue_dhcp`；临时关闭 `uci set firewall.rogue_dhcp_include.enabled=0; uci commit firewall; fw4 reload`。
> **Homebox**：默认自启 `http://192.168.1.1:3300`，LuCI「服务 → Homebox」；init.d 已适配 v1.0.1 的 `serve` 子命令。

> 「网络 → DHCP/DNS」页面是 `dnsmasq`（仅 DHCP + 缓存，不配上游），属系统基础设施**不是 DNS 插件**，不能删；SmartDNS 整组已移除。若 LuCI 里仍出现「SmartDNS」菜单，是旧配置残留，重刷时不要勾「保留配置」或执行 `DNS_现机清理.sh`。：`dns_shunt=chinadns-ng` + `dns_redirect=1`；系统 dnsmasq 只留 DHCP/缓存，不配上游；SmartDNS 已整组移除 |
> | DDNS | **只留花生壳 `oray.com`**：Lucky 移除，首启清掉其余 93 个 provider |
> | 测速 | 只留 `FastNet`（Homebox 移除） |
> | 商店/主题 | iStore 移除（用 FastNet + apk 界面）；ARGON 主题 |
> | 出厂默认 | `192.168.1.1` / `root` `admin`、Asia/Shanghai、内网 NTP + option 42、IPv6 关闭、5G WiFi CN/HE160 |
> | 发布 | 固件文件名末段 `YYYYMMDD-HHMM` 为编译日期（上海时间）；每次按时间新建 Release `fw-<机型>-<时间戳>-r<run>a<attempt>`，**只保留最近 5 次**；**下载页并列两个裸 `.itb`（刷机 + 救砖），不压缩、不用解压**，说明页只列机型/默认配置/插件 |
>
> 完整清单见 `固件发布日志.md` / `插件冲突排查报告.md` / `上传与核对说明.md`。

## 快速开始

免费 runner 单次上限 6 小时（job 350 分钟），首次全量编译（工具链 + 内核 + 全包）大概率超时，按这个顺序跑：

1. **Warm Build Cache** → `soc=an7581和an7583`、`prebuilt_host=预编译`，把工具链缓存建起来
2. **Build PonWrt** → 选 `soc` / `profile` → `scope=firmware` 出固件
3. 仍然超时：改 **两份机型 config**（`configs/fiberhome_hg5585f-ct.config` / `configs/nokia_xg-040g-md-ubi.config`）里不需要的 luci-app / 语言包再提交；不要动 `configs/an7581.config` 等通用配置

> 不预热也能直接跑 `firmware`——缓存是滚动式的，第一次跑完会自动存下工具链。预热只是给怕超时的人用的。

## 输入项

### `build-ponwrt.yml`

| 输入 | 取值 | 说明 |
|---|---|---|
| `source` | `pbs05/ponwrt` / `fork` | 编译哪个源码仓库。**必须和缓存预热时选的一致**，否则前缀对不上 |
| `branch` | 默认 `master` / `wifi7-an4475` | AN4475-G2 用 vendor Wi-Fi 7 驱动时填 `wifi7-an4475`（需 `source=fork`）；分支进缓存 key 前缀，预热与主流程必须一致 |
| `soc` | `an7581` / `an7583` | |
| `profile` | 见下方机型表，`all` = 全机型 | 写错会在 `Validate configuration` 直接报错退出，不会静默全编 |
| `scope` | `firmware` / `toolchain-only` | 后者只建工具链缓存，不出固件、不发 Release |
| `prebuilt_host` | `true`（默认）/ `false` | `true` 用 runner 的 Go/Rust/LLVM，快 1.5~2.5 小时；`false` 全部从源码编，产物可复现 |
| `ignore_cache` | `false` / `true` | 跳过缓存恢复强制重编（仍会存新一代） |
| `upload_release` | `true` / `false` | `false` 只留 Artifact |
| `opt_arm64ce` / `opt_chacha` / `opt_eip93` | `0` / `1` | 加密加速，见文末 |

### 四个工作流

| 工作流 | 触发 | 作用 |
|---|---|---|
| `build-ponwrt.yml` | 手动 | 恢复缓存 → 编译 → 存缓存 → 轮换旧代 |
| `warm-cache.yml` | 手动 / 每周一 03:17 | 预热。`soc` 和 `prebuilt_host` 都是三选一，两个都选「和」的选项 = 4 个 job 并行 |
| `cache-keepalive.yml` | 每 3 天 | 逐条真实恢复，避开 `actions/cache` 的 7 天未访问回收 |
| `cache-clean.yml` | 手动 / 每周一 04:20 | `rollover` 每族留最新一代 / `backup` 只清 Release 备份 / `all` 全删 |

## 支持的机型（本 fork 实际维护的）

| SoC | profile | 配置 | 说明 |
|---|---|---|---|
| AN7581 | `fiberhome_hg5585f-ct` | `configs/fiberhome_hg5585f-ct.config` | 带 MT7916D WiFi、分页式 BOSA、GPY211 2.5G PHY |
| AN7581 | `nokia_xg-040g-md-ubi` | `configs/nokia_xg-040g-md-ubi.config` | 无 WiFi；EN7572 光前端 + EN8811H PHY |

**Build PonWrt 的 `profile` 下拉只有这两项**。`all` 已停用：它原来会加载
`configs/an7581.config` / `an7583.config`，这两份仍是上游旧状态（Lucky /
OpenClash / MosDNS / SmartDNS / Tailscale / EasyTier / Fluent / Airoha feed
四包都还是 `=y`），会在 `Load custom configuration` 的插件去重硬校验处直接
`exit 1`，连 `make` 都进不去（run `45094702535` 就是这么挂的）。

仓库里其余 14 份 `configs/*.config` 与 `AN4475-G2 / Wi-Fi 7 / FTTR` 相关章节
是**上游遗留文档**，本 fork 不维护、不参与构建，仅供查阅。

## AN4475-G2 vendor Wi-Fi 7 云编译（`wifi7-an4475` 分支）

原厂无线栈是 MediaTek **vendor full-MAC** 驱动（`mt_wifi` / `mtk_hwifi` / `mt7993` / `mt799b` / `wifi-profile`），不是 mt76/mac80211。`qwe-qaq/ponwrt@wifi7-an4475` 分支已把这套包放进 `package/custom/`，并**删除了 DTS 里的 `mediatek,mt76` PCIe 子节点**，让 vendor 驱动按 PCI `14c3:7993` / `14c3:799b` 绑定。两条路线互斥：

| | `master` + `configs/fiberhome_an4475-g2.config` | `wifi7-an4475` + `configs/fiberhome_an4475-g2-wifi7.config` |
|---|---|---|
| 驱动 | mt76 / mac80211（`kmod-mt7996e` + `kmod-mt7990-firmware`） | vendor full-MAC（`kmod-mt_wifi7` / `mt_hwifi` / `mt7993` / `mt799b`） |
| DTS | 有 `mt7990@0,0 { compatible = "mediatek,mt76" }` | 已删除该子节点 |
| 固件 | `mt7990_wm.bin` / `rom_patch` | `WIFI_RAM_CODE_MT7993_1_1.bin` / `WIFI_MT7993_PATCH_MCU_1_1_hdr.bin` / `MT7993_EEPROM.bin` |
| NPU 固件 | `en7581_npu_*.bin`（`airoha-en7581-npu-firmware`） | `en7581_MT7996_npu_*.bin`（`airoha-en7581-mt7996-npu-firmware`，与 DTS `firmware-name` 一致） |
| 校准 | mt76 默认 | `wifi_e2p.init` 从 Factory 分区提取 `e2p`（`0x14a800`） |

### 运行步骤

1. **Warm Build Cache**（可选但推荐）→ `soc=an7581`、`source=fork`、**`branch=wifi7-an4475`**、`prebuilt_host=预编译`。缓存 key 含分支，预热与主流程必须填**同一个**分支。
2. **Build PonWrt** → `source=fork`、**`branch=wifi7-an4475`**、`soc=an7581`、`profile=fiberhome_an4475-g2`、`scope=firmware`、`prebuilt_host=true`。
3. `Resolve device profile` 检测到 `REPO_BRANCH=wifi7-an4475` 会自动把 `CONFIG_FILE` 切到 `configs/fiberhome_an4475-g2-wifi7.config`，并导出 `WIFI7_VENDOR=true`；`Validate configuration` 会额外校验 vendor 包、MTK SDK Kconfig 符号、L1 profile 是否都在 defconfig 后存活，以及 mt76 冲突包是否已关闭。
4. 产物在 Artifact `OpenWrt_firmware_ponwrt-an7581-fiberhome_an4475-g2-prebuilt*` 与 Release tag `ponwrt-an7581-fiberhome_an4475-g2-prebuilt-wifi7-an4475`。

> 用 `pbs05/ponwrt` 或 `master` 跑 AN4475-G2 时保持原样即可（mt76 路线），本改动不会影响其它机型。

### 配置要点（`configs/fiberhome_an4475-g2-wifi7.config`）

- `CONFIG_PACKAGE_kmod-mt_wifi7` / `mt_wifi_osal` / `mt_hwifi` / `mtk_pci` / `connac_if` / `mt7993` / `mt799b` / `wifi-profile` / `mtwifi-cfg-ucode` / `mwctl` 全部 `=y`，与源码树 `image/an7581.mk` 的 `DEVICE_PACKAGES` 逐项对账（`Validate configuration` 会核对 `tmp/.targetinfo` 的 `Target-Profile-Packages`）。
- `CONFIG_MTK_HWIFI_MT7993=y` / `MT799B=y`：这两个符号在 `config.in` 里**没有 default y**，不写就选不中芯片包，且 `mt_hwifi/Makefile` 的 MT7993 固件安装块也不会执行。`RRO_MODE=5` / `OPTION_TYPE=1` / `INTR_OPTION_SET=4` 对齐原厂 EN7581 加载参数。
- `CONFIG_MTK_WIFI7_CHIP_MT7993=y`：触发 `mt_wifi7/Makefile` 安装 `MT7993_EEPROM.bin` 与 iPAiLNA / ePAeLNA 默认 bin。
- `CONFIG_DRIVER_11AC/AX/BE_SUPPORT=y`：`mt_wifi7` 的 `DEPENDS` 带 `+@DRIVER_11*` 三个符号，默认全是 n。
- `CONFIG_first_card_*`（`name="MT7993"`、`EEPROM_size="0x14a800"`、`EEPROM_name="e2p"`、`main_ifname="ra0;rai0"`），并显式 `# CONFIG_second_card is not set` / `# CONFIG_third_card is not set`（`l1profile.config.in` 里两者默认 y，是 MT7615）。`make-l1profile.py` 只认 `.config` 里显式出现的行，缺了会生成只有 `Default` 的空 `l1profile.dat`。
- `EEPROM_name` 必须用 `e2p`：`wifi_e2p.init` 在 `/lib/firmware/$FIRMWARE` 已存在时直接 return，若写 `MT7993_EEPROM.bin` 会命中包内自带的 7680 B 默认 blob，**跳过从 Factory 分区提取设备专属校准数据**。
- **不要**启用 `MTK_WIFI7_FAST_NAT_SUPPORT` / `WHNAT_SUPPORT` / `CONNINFRA_APSOC` / `MTK_HWIFI_WED_SUPPORT` / `EN_HWIFI_NPU_SUPPORT`：它们会引入本树不存在的 `kmod-mediatek_hnat` / `kmod-conninfra` / `kmod-warp`。参考仓库的 `mt7987-mt7993-be3600.config` 不能照搬。

### 编译后仍需实机验证

CI 只能证明「编译通过、镜像里固件齐全」，不能证明「加载成功、稳定联网」。刷机后请核对：`lspci -nn` 有 `14c3:7993`/`14c3:799b`、`lsmod` 中 vendor 模块按 AUTOLOAD 61→66 全部加载、`dmesg` 无 `request_firmware` 失败与 `Unknown symbol`、`/lib/firmware/e2p` 约 `0x14a800`、`iw dev` 生成 `ra0`/`rai0`、`wifi status` 正常，以及吞吐 / 长时间稳定性。

## 插件开关（`diy-part1.sh`）

⚠ **旧版说明「开关与两个通用 config 一一对应、要关插件改通用 config」已作废。**
现在 `profile=<机型>` 时**只认 `configs/${PROFILE}.config`**，两份通用 config 完全不参与。

### 当前编入的插件（两组 config 软件部分一致）

| 分类 | 包 |
|---|---|
| 光猫 | `luci-app-onu` + 中文、`luci-app-pon-status`、`luci-app-natmode`、`luci-app-airoha-npu`（只读状态页） |
| 组播 | `omcproxy` + `igmpproxy` + `luci-app-igmpproxy`、`rtp2httpd` v3.17.2 + LuCI + 中文；IGMP Snooping 由 `99-zz-igmp-snooping` 首启开启 |
| DNS / 代理 | `luci-app-passwall` + `xray-core` / `sing-box` / `chinadns-ng` / `dns2socks` |
| DDNS | `ddns-scripts` + `luci-app-ddns` + `ddns-scripts-services`（运行期收敛到只剩 `oray.com.json`） |
| 测速 | `fastnet` / `luci-app-fastnet` / `linkease-app-entry` |
| 系统 | `ttyd`、`watchdog`（登录失败拉黑）、`taskplan`、`accesscontrol-plus`、`vantage`、`nft-qos`、`luci-app-package-manager` |
| USB 打印 | `p910nd` / `printer-support` / `luci-app-usb-printer` + 全套 USB 内核模块 |
| 主题 | `luci-theme-argon`（bootstrap 是 LuCI 基础主题，保留） |

**简体中文包 14 个**。完整逐项见 `固件发布日志.md`。

### 已移除 / 白开（别被旧文档骗）

`iStore`、`luci-app-airoha` feed 四页面、旧 `luci-app-pon`、`Homebox`、
`Lucky`、`SmartDNS`、`OpenClash`、`MosDNS`、`Tailscale`、`EasyTier`、
`Fluent` 主题、`OAF`、`FTTR` —— 全部不编入。其中 `ADD_OPENCLASH` /
`ADD_MOSDNS` / `ADD_TAILSCALE` / `ADD_EASYTIER` / `ADD_FLUENT` 等开关已置
`false`（原来「开关 true 但 config 无 `=y`」属白 clone，拖 Ruby/Rust 白等时间）。

### 想增删插件，改哪里

**改两处，且都在这两份文件里**：

1. `configs/fiberhome_hg5585f-ct.config` 和 `configs/nokia_xg-040g-md-ubi.config`
   里写 `CONFIG_PACKAGE_<包名>=y`（或 `is not set`）
2. `diy-part1.sh` 里对应的 `ADD_xxx` 开关 + clone/拷包逻辑

只改一处不生效：只改 config → 源码没进 `package/custom/`，`make defconfig`
静默剔除；只改 diy → 白 clone 一份不进固件的源码。

> `profile=all` 已停用，`configs/an7581.config` / `an7583.config` 只被
> `warm-cache.yml` 用来预热工具链（且预热时会把已剔除插件的 `=y` 过滤掉）。
> 它们**不影响固件内容**。

## 构建缓存（移植自 VIKINGYFY/OpenWRT-CI）

一份缓存 = 三个目录：

```
staging_dir/host*      host 工具 + hostpkg（go / python 在这）
staging_dir/tool*      交叉编译器
.ccache                编译对象缓存
```

**tools / toolchain 会不会重编，取决于 `staging_dir` 里的 compile 戳，不取决于缓存里
有没有 `build_dir`。** `make world` 的 `prepare` 依赖
`staging_dir/host/stamp/.tools_compile_<flags>` 和 `staging_dir/toolchain-*/stamp/.toolchain_compile`，
这两个戳存在且比源码树新，`tools/compile` 与 `toolchain/compile` 就整段跳过。

**但 host 包（golang / rust / python3）是另一回事。** 它们有四个戳，被拆在两处：
`staging_dir/hostpkg/stamp/.<pkg>_installed` 跟着缓存走，而
`build_dir/host/<pkg>/.built`、`.configured`、`.prepared_<md5>` 不在缓存路径里。
依赖链是 `installed ← built ← configured ← prepared`，缺了 built 这一层，make 就认为没编过，
整条链重做。**这就是 source 模式比 prebuilt 慢 20~40 分钟、多写 13~14 GB 的原因**——
golang 和 rust 每轮都在从源码自举。

所以 source 模式在编译结束时会把这三个戳单独冻一份到
`staging_dir/host/.builddir-stamps/`（只冻戳，不冻内容：100 来个包 × 3 个空文件，
压缩后不到 10 KB），下一轮 `prepare` 原样还原，mtime 保持不变。
**prebuilt 模式不冻**——那里的 go/rust 是指向 runner 的符号链接，换镜像后可能悬空，
宁可让同一条链重跑一遍自愈（`rust-prebuilt.mk` 已把 Prepare/Configure/Compile 置空，只花几秒）。

**精确命中 = 这份缓存就是当前这个提交编出来的**，两条通道都算：`actions/cache` 的
`cache-hit=true`，或 Release 资产名去掉 `.tzst` 后与本次 key 完全相同。只有精确命中时
`prepare` 才保留这两个戳；前缀回退、或 Release 取到的是旧代，都说明源码已变，脚本会删掉
它们迫使 make 重编（约 26 分钟，ccache 会加速）。当前提交通常在第一次构建时付这 26 分钟，
之后同提交重跑都是 0 分钟。

> 冻进去的 `build_dir` 戳不会误跳编译：`.prepared` 的文件名里带着包源码目录的内容 MD5
> （`PKG_FILES_MD5`），上游一改源码戳名就对不上，make 自然重建。target 侧的戳则完全不在
> 缓存里，所以固件包每轮照常重编。

| 通道 | 介质 | 特点 |
|---|---|---|
| ① 快通道 | `actions/cache` | 秒级，但 **7 天无访问即回收** |
| ② 备份通道 | ~~Release `cache-backup`~~ | **2026-11-23 默认关闭**：下载页不再出现缓存文件；靠 `cache-keepalive.yml` 每 3 天真实恢复保活快通道 |

恢复 ①→②，保存时两条都写（② 失败只 warning）。key 规则：

| | key |
|---|---|
| 写入 | `ponwrt-<源站>-<分支>-<SoC>-<prebuilt\|source>-<上游提交号>` |
| 恢复 | 同上前缀 + `-`（**前缀回退**） |

前缀不含配置、机型、diy 脚本——改这些不会让缓存失效；上游一提交就换一代，靠 `restore-keys` 回退到最近一代。旧代由 `cache-rollover` job 删掉，保证每个前缀只留一份。

**恢复后必须做三件事**（`scripts/pwrt-cache.sh prepare`），少一件就等于白命中：touch 非 target 的 stamp、写 `tmp/.build`、touch 目录本身。

**dl 缓存**（源码包，2~5 GB）单独一条，key 按周滚动 `ponwrt-dl-<源站 slug>-<分支>-<YYYYWW>`（`pbs05/ponwrt` → `pbs05-ponwrt`，与工具链 key 同一套规则）。保存在 `make download` 之后、编译之前——350 分钟一到 job 直接 cancel，放最后用 `always()` 也来不及跑。

**两种 host 模式不共用缓存**：`HOST_MODE` 进前缀。prebuilt 在 `staging_dir` 里留的是指向 runner 的符号链接，source 留的是真二进制，混用会让 make 误判「已安装」并在编译期报一个完全对不上的错。**warm-cache 必须和主流程选同一个模式**，否则预热白跑。

**rust 包的离线限制**：`openwrt-fttr` 的 Makefile 用 `cargo install --locked --frozen`，`--frozen` 禁止联网、只认 `dl/cargo` 里已有的 crate。`scripts/patch-cargo-offline.sh` 把 `--frozen` / `--offline` 摘掉，`--locked` 保留（版本仍锁死）。

## 客制化

| 位置 | 做了什么 |
|---|---|
| `files/sbin/cpuusage` + `scripts/patch-luci-cpuusage.sh` | 概览页 CPU 行改为 `USR: 2% SYS: 1% · CPU0 3% CPU1 0%…`（两次 `/proc/stat` 采差值，USR=`user+nice`、SYS=`system+irq+softirq`）。补丁只换 `popen()` 里一个命令字符串，前端和 ACL 都不动；任一环节失败只 warning，构建不受影响 |
| `files/sbin/tempinfo` | 概览页温度行：CPU / WiFi / PON 三个温度。顶部 `SHOW_PON_OPTICS=1` 可附带收发光/电流/电压（默认 0，因为 `luci-app-pon-status` 卡片已经完整展示，重复） |
| `diy-part2.sh` | 默认时区 `Asia/Shanghai`、5G 国家码 `CN` / 信道 `auto` / 频宽 `HE160`（不支持时回落到 `HE80`）、固件版本后缀追加作者与构建时间 |
| `files/etc/uci-defaults/` | 首启强制刷时区与无线参数的兜底脚本 |

## NPU 固件

NPU 是 Airoha SoC 里的 RISC-V 核，host 侧驱动随内核编出，按固定名字找两个镜像：

| 镜像 | 文件名 | 上限 |
|---|---|---|
| rv32（text+rodata） | `airoha/en7581_npu_rv32.bin`（AN7583 为 `an7583_*`） | 2 MiB |
| data | `airoha/en7581_npu_data.bin` | 64 KiB |

由 ponwrt 自带的 linux-firmware 提供，在 `configs/<机型>.config` 写 `CONFIG_PACKAGE_airoha-en7581-npu-firmware=y` 即装进 rootfs。工作流不介入固件生成——要换就改这一行。

```sh
dmesg | grep -i npu           # probe 时打 fw version
ls -l /lib/firmware/airoha/   # 两个 bin 在位
```

缺文件或名字不符 → `-ENOENT` → 映射成 `-EPROBE_DEFER`，NPU 一直不绑定（`deferred probe pending` 里能看到具体文件名）；超限 → `-E2BIG`。

## 加密加速（可选）

| 开关 | 建议 | 适用 |
|---|---|---|
| `opt_arm64ce` | 改 `1` | IPSec / OpenVPN / TLS / dm-crypt，几乎总是开 |
| `opt_chacha` | 改 `1` | 跑 Xray / sing-box / WireGuard |
| `opt_eip93` | 保持 `0` | 只有大块 IPSec / 大文件 TLS 才有收益 |

**AN7581 和 AN7583 不一样**：AN7581 的 `/proc/cpuinfo` 里没有 `aes`，`/proc/crypto` 只有 `aes-generic`，单核 AES-128-GCM 约 32 MB/s，只能走 NEON 位切片（`AES_ARM64_BS`）；AN7583 有 `aes pmull sha1 sha2`，同样测试约 548 MB/s，可以走 Crypto Extensions。脚本读 `.config` 自动判断，不用手动切。

**EIP93 是个陷阱**：AN7581 确实内置（`crypto@1e004000`），但实测 AES 要 ≥512 字节才快过软件，MD5/SHA1/SHA2 在所有尺寸下都是软件更快，代理流量开着只会更慢。

验证：

```sh
grep -ao 'aes\|pmull\|sha1\|sha2' /proc/cpuinfo | sort -u   # AN7581 不会有 aes
cat /proc/crypto | grep -E '^name|^driver|^priority'
openssl speed -evp aes-128-gcm
openssl speed -evp chacha20-poly1305
```

> `CONFIG_CRYPTO_*` 是**内核编译符号**，必须写进 `target/linux/airoha/an7581/config-<kver>`。写进顶层 `.config` 会被 target config 覆盖——看起来配上了，实际不生效。

## 排错

| 症状 | 先看哪里 |
|---|---|
| `defconfig` 失败 | 日志里 `make defconfig` 那段的尾部 60 行 + 根因提示（`scripts/defconfig.sh` 输出） |
| 关键包「未启用，检查 feeds」 | 多数是上一步 defconfig 失败的连带；独立出现时查 `tmp/.packageinfo` 里有没有该包 |
| `Failed to download` / 编译期报缺 crate | `make download` 三次都失败会直接 error 退出，去那段输出搜 `ERROR:` |
| 缓存「命中」却仍然全量重编 | `prepare` 那步的三件事是否都做了；`Build host go/rust from source` 的 warning |
| 缓存永远 miss | `source` / `branch` / `soc` / `prebuilt_host` 四项是否和预热时一致 |
| `artifacts` 上传失败 | Artifact 存储配额（默认保留 90 天，几份固件就可能超） |
| NPU 不绑定 | `dmesg \| grep -i npu`、`/lib/firmware/airoha/` 里的文件名和大小 |

## 已知限制

- 只有 `scope=firmware` 且编译成功才发 Release；`toolchain-only` 不发，空固件目录会跳过。
- Release 每次按上海时间新建独立 tag `fw-<机型>-<YYYYMMDD-HHMMSS>-r<run>a<attempt>`，**只保留最近 5 次**（只删 `fw-` 前缀）；固件**两个裸 `.itb` 并列**（`squashfs-sysupgrade` + `initramfs-recovery`），**不再压缩**；buildinfo / manifest / profiles.json 只在 Artifact；`cache-backup` 已默认关闭并自动清理，不再出现在下载页。
- NPU 只在三层路由模式生效，纯 AP 桥接时整机吞吐会掉到 2000 Mbps 左右。
- `repository_dispatch` 触发时所有 choice 输入都是空，走 env 回退值：`PROFILE=fiberhome_hg5585f-ct`、`SOC=an7581`、`scope=firmware`。
- 网页上传会把 `.sh` / uci-defaults 存成 `100644`（丢执行位）；`build-ponwrt.yml` 在编译前统一 `chmod +x`，走 CI 不受影响，脱离 CI 手动打包才需要自己补。


---

## 组播：每个桥 / 每个网口（2026-11-25）

**IGMP Snooping 是桥属性，不是物理端口属性**；端口上能设的是
`multicast_router` / `multicast_fast_leave` / `multicast_to_unicast`。
本版对**每一个** bridge 开 `multicast_snooping=1` + **`multicast_querier=1`**
（没有 querier 时 MDB 约 125 秒老化，IPTV 两分钟后断流），
并对该桥**每一个端口**（有线 LAN、WiFi、CPU）逐个套用参数。
`ALL_PORTS_MROUTER=2` 可切到「每口都收全量组播」，但高码率 IPTV 会泛洪到 WiFi，慎用。

组播 WAN 上游仍需 `igmpproxy` 或 `omcproxy` **二选一启用**（模板已给，不自动 enable）；
详见 `上传与核对说明.md`。核对：
`bridge mdb show`、`cat /sys/class/net/br-lan/bridge/multicast_querier`、
`nft list table inet multicast_allow`。


---

## 上网时间控制 Plus / PassWall 服务状态（2026-11-25）

**上网时间控制 Plus** 原本是 fw3/iptables 时代的包，本固件是 fw4 + 纯 nftables，
`iptables` 命令不存在，所以状态永远「未运行」。本版把它换成 nftables 后端：
`table inet miaplus` 的 forward 链按 MAC drop，由 cron 每分钟按星期/时刻重建，
**完全不碰 53 端口**，不再与 PassWall 抢 DNS。出厂 `enable=1` 但规则为空
（＝运行状态、不限制任何客户端）；在「Base Setting → 客户端规则」加 MAC + 模板、
在「高级设置」编辑时间段后才真正管控。核对：

```sh
nft list table inet miaplus
crontab -l | grep miaplus
logread -e miaplus
```

**PassWall 已装但不会自动启用**：固件不预置节点，`app.sh` 只有
`(enabled=1 且 NODE 有效)` 才启动代理。首页 TCP/UDP/DNS「未运行」是设计，
不是故障。三步：**节点订阅 → 添加并更新 → 节点列表选节点 → 基本设置勾「启用」**
（开机自启另有 60 秒延时）。首页「GitHub 连接失败」是浏览器直连测试，不用管。
完整说明见 **`PassWall_启用引导.md`**。
