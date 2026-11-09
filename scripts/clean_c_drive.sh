#!/usr/bin/env bash
# C 盘零风险档清理(默认 dry-run,加 --apply 才实际执行)
# 用法: bash clean_c_drive.sh [--apply] [用户名]
# 清理范围(第一档,均可再生/重建):
#   1. Temp 中 24h 未改动条目 + 1h 前的 _MEI* PyInstaller 残留(跳过 zcode-bash-*)
#   2. npm / Yarn / uv / pip 缓存(用官方命令清)
#   3. VS Code 扩展安装包缓存 CachedExtensionVSIXs
# 禁区: 微信/QQ/钉钉数据、Documents、浏览器 Profile、Windows\Installer 一律不碰

set -u
chcp.com 65001 >/dev/null 2>&1

APPLY=0
USER_NAME="Administrator"
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    *)       USER_NAME="$a" ;;
  esac
done
U="/c/Users/$USER_NAME"
[ -d "$U" ] || { echo "错误: 用户目录不存在: $U" >&2; exit 1; }

MODE="[dry-run]"; [ "$APPLY" = "1" ] && MODE="[apply]"
free_gb() { powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\" | ForEach-Object { '{0:N1}' -f (\$_.FreeSpace/1GB) }" 2>/dev/null | tr -d '\r'; }
BEFORE=$(free_gb)
echo "=== C 盘零风险清理 $MODE 用户:$USER_NAME ==="
echo "清理前剩余: ${BEFORE} GB"
echo

# 1. Temp(24h 未改动 + 跳过 zcode 会话;_MEI* 只清 1h 前的,避免伤到正在运行的 PyInstaller 程序)
TEMP="$U/AppData/Local/Temp"
if [ -d "$TEMP" ]; then
  SIZE=$(du -sm "$TEMP" 2>/dev/null | cut -f1)
  N=$(find "$TEMP" -maxdepth 1 ! -name "zcode-bash-*" ! -name "Temp" -mtime +1 2>/dev/null | wc -l)
  M=$(find "$TEMP" -maxdepth 1 -name "_MEI*" -mmin +60 2>/dev/null | wc -l)
  echo "1) Temp 目录 ${SIZE}MB:${N} 个 24h 前条目 + ${M} 个 _MEI* 残留"
  if [ "$APPLY" = "1" ]; then
    find "$TEMP" -maxdepth 1 ! -name "zcode-bash-*" ! -name "Temp" -mtime +1 -exec rm -rf {} + 2>/dev/null
    find "$TEMP" -maxdepth 1 -name "_MEI*" -mmin +60 -exec rm -rf {} + 2>/dev/null
    echo "   已清理"
  fi
fi

# 2. 包管理器缓存(官方命令;pip 在 Git Bash 常不在 PATH,回退 python -m pip)
declare -A CMDS=( [npm]="npm cache clean --force" [yarn]="yarn cache clean" [uv]="uv cache clean" )
i=2
for tool in npm yarn uv; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "$i) $tool 缓存: ${CMDS[$tool]}"
    [ "$APPLY" = "1" ] && { ${CMDS[$tool]} >/dev/null 2>&1; echo "   已清理"; }
    i=$((i+1))
  fi
done
if command -v pip >/dev/null 2>&1; then
  echo "$i) pip 缓存: pip cache purge"
  [ "$APPLY" = "1" ] && { pip cache purge >/dev/null 2>&1; echo "   已清理"; }
  i=$((i+1))
elif command -v python >/dev/null 2>&1; then
  echo "$i) pip 缓存: python -m pip cache purge"
  [ "$APPLY" = "1" ] && { python -m pip cache purge >/dev/null 2>&1; echo "   已清理"; }
  i=$((i+1))
fi

# 3. VS Code 扩展安装包缓存
VSIX="$U/AppData/Roaming/Code/CachedExtensionVSIXs"
if [ -d "$VSIX" ]; then
  SIZE=$(du -sm "$VSIX" 2>/dev/null | cut -f1)
  echo "$i) VS Code CachedExtensionVSIXs ${SIZE}MB"
  [ "$APPLY" = "1" ] && { rm -rf "$VSIX"; echo "   已清理"; }
fi

echo
AFTER=$(free_gb)
echo "清理后剩余: ${AFTER} GB"
[ "$APPLY" = "0" ] && echo "(dry-run 未执行任何删除;确认无误后加 --apply 执行)"
