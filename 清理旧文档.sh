#!/bin/sh
# 文档合并后的清理：把 6 份已并入《固件修复与配置总览.md》的旧文档删掉。
# 在仓库根目录执行：sh 清理旧文档.sh && git add -A && git commit ...
# ⚠ 不要删 README.md（项目说明）和 RELEASES.md（workflow 自动写目标）。
set -e
for f in \
  PassWall_启用引导.md \
  上传与核对说明.md \
  修复说明.md \
  固件发布日志.md \
  固件配置与服务总览.md \
  插件冲突排查报告.md
do
  if [ -f "$f" ]; then
    git rm -f "$f"
    echo "  ✅ 已删除 $f"
  else
    echo "  ⏭ 不存在，跳过 $f"
  fi
done
echo
echo "仓库根目录现在应只剩 3 个 .md：README.md / RELEASES.md / 固件修复与配置总览.md"
ls -1 *.md
# 一次性脚本：执行完自删，仓库里不会多出一个没人再用的文件
rm -f "$0" 2>/dev/null || true
echo "  ✅ 清理脚本已自删"
