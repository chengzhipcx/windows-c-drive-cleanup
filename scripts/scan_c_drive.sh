#!/usr/bin/env bash
# Windows C 盘空间分层扫描(Git Bash 环境运行)
# 用法: bash scan_c_drive.sh [选项] [用户名]
#   --tier1   只扫已知热点(最快,约 1 分钟)
#   --tier2   tier1 + AppData 全量扫描(默认)
#   --tier3   tier2 + C 盘顶层目录(最慢,可能数分钟)
#   --json    以 JSON 输出(便于程序处理)
#   用户名默认 Administrator

set -u
chcp.com 65001 >/dev/null 2>&1

TIER=2
JSON=0
USER_NAME="Administrator"
for a in "$@"; do
  case "$a" in
    --tier1) TIER=1 ;;
    --tier2) TIER=2 ;;
    --tier3) TIER=3 ;;
    --json)  JSON=1 ;;
    *)       USER_NAME="$a" ;;
  esac
done
U="/c/Users/$USER_NAME"
[ -d "$U" ] || { echo "错误: 用户目录不存在: $U" >&2; exit 1; }

# ---------- 数据收集 ----------
DISK_LINE=$(powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\" | ForEach-Object { '{0:N1}' -f (\$_.FreeSpace/1GB) }" 2>/dev/null | tr -d '\r')
FREE_GB="${DISK_LINE:-?}"

# 输出 "MB<tab>路径" 行;路径不存在则跳过
du_mb() { du -sm "$@" 2>/dev/null | sort -rn; }

PAGEFILE=$(ls -la /c/ 2>/dev/null | grep -iE "pagefile|hiberfil|swapfile" | awk '{printf "%s %.0fMB; ", $NF, $5/1048576}')
VHDX=$(find "$U" -maxdepth 5 -name "*.vhdx" 2>/dev/null | head -3 | tr '\n' ';')

T1_PATHS=(
  "$U/AppData/Local/Temp" "$U/AppData/Local/npm-cache" "$U/AppData/Local/Yarn"
  "$U/AppData/Local/uv" "$U/AppData/Local/pip" "$U/AppData/Local/pnpm"
  "$U/AppData/Local/ms-playwright" "$U/AppData/Local/Docker" "$U/AppData/Local/Google"
  "$U/AppData/Local/Microsoft" "$U/AppData/Local/Programs" "$U/AppData/Local/JetBrains"
  "$U/AppData/Local/NVIDIA" "$U/AppData/Roaming/Code/CachedExtensionVSIXs"
  "$U/.bun" "$U/.cache" "$U/.ollama" "$U/miniconda3" "$U/anaconda3"
  "$U/Downloads" "$U/Documents" "$U/.vscode/extensions"
)
T1_DATA=$(du_mb "${T1_PATHS[@]}")

MEI_COUNT=$(find "$U/AppData/Local/Temp" -maxdepth 1 -name "_MEI*" 2>/dev/null | wc -l)
CHROME=$(du_mb "$U/AppData/Local/Google/Chrome/User Data/Default/Cache" \
               "$U/AppData/Local/Google/Chrome/User Data/Default/Code Cache" \
               "$U/AppData/Local/Google/Chrome/User Data/Default/GPUCache" 2>/dev/null)

SYS_DATA=$(du_mb /c/Windows/SoftwareDistribution/Download /c/Windows/Temp \
                 /c/Windows/Installer '/c/$Recycle.Bin' /c/Windows/LiveKernelReports 2>/dev/null)
WINDOWS_OLD="no"; [ -d /c/Windows.old ] && WINDOWS_OLD="yes"

T2_LOCAL=""; T2_ROAM=""
if [ "$TIER" -ge 2 ]; then
  T2_LOCAL=$(du_mb "$U/AppData/Local"/* 2>/dev/null | awk '$1>300')
  T2_ROAM=$(du_mb "$U/AppData/Roaming"/* 2>/dev/null | awk '$1>100')
fi

T3_DATA=""
if [ "$TIER" -ge 3 ]; then
  T3_DATA=$(du_mb /c/Users /c/Windows "/c/Program Files" "/c/Program Files (x86)" /c/ProgramData 2>/dev/null)
fi

CACHE_CFG=$(powershell -NoProfile -Command "'UV_CACHE_DIR=' + [Environment]::GetEnvironmentVariable('UV_CACHE_DIR','User'); 'YARN_CACHE_FOLDER=' + [Environment]::GetEnvironmentVariable('YARN_CACHE_FOLDER','User'); 'BUN_INSTALL=' + [Environment]::GetEnvironmentVariable('BUN_INSTALL','User')" 2>/dev/null | tr -d '\r')
NPM_CACHE=$(npm config get cache 2>/dev/null)

# ---------- 输出 ----------
if [ "$JSON" = "1" ]; then
  jpath() { # 把 du 输出转 JSON 数组元素(空输入返回空,保证 JSON 合法)
    [ -z "$1" ] && return
    echo "$1" | awk -F'\t' 'NF>=2 {printf "{\"mb\":%s,\"path\":\"%s\"},", $1, $2}' | sed 's/,$//'
  }
  jesc() { # JSON 字符串转义:反斜杠与换行
    printf '%s' "$1" | sed 's/\\/\\\\/g' | tr '\n' ';' | sed 's/;$/;/'
  }
  printf '{\n'
  printf '  "c_free_gb": %s,\n' "$FREE_GB"
  printf '  "pagefile": "%s",\n' "$(jesc "$PAGEFILE")"
  printf '  "vhdx": "%s",\n' "$(jesc "$VHDX")"
  printf '  "mei_residue": %s,\n' "$MEI_COUNT"
  printf '  "windows_old": "%s",\n' "$WINDOWS_OLD"
  printf '  "tier": %s,\n' "$TIER"
  printf '  "hotspots": [%s],\n' "$(jpath "$T1_DATA")"
  printf '  "chrome_caches": [%s],\n' "$(jpath "$CHROME")"
  printf '  "system_cleanable": [%s],\n' "$(jpath "$SYS_DATA")"
  printf '  "appdata_local_over_300mb": [%s],\n' "$(jpath "$T2_LOCAL")"
  printf '  "appdata_roaming_over_100mb": [%s],\n' "$(jpath "$T2_ROAM")"
  printf '  "top_level": [%s],\n' "$(jpath "$T3_DATA")"
  printf '  "cache_config": "%s"\n' "$(jesc "$CACHE_CFG")"
  printf '  , "npm_cache": "%s"\n' "$(jesc "$NPM_CACHE")"
  printf '}\n'
  exit 0
fi

fmt() { echo "$1" | awk -F'\t' '{printf "%8.2f GB  %s\n", $1/1024, $2}'; }

echo "=== C 盘剩余: ${FREE_GB} GB (tier$TIER) ==="
echo
echo "=== 误判项 ==="
echo "页面/休眠文件: ${PAGEFILE:-无}"
echo "WSL vhdx: ${VHDX:-无}"
echo "Windows.old: $WINDOWS_OLD"
echo
echo "=== 已知热点 ==="
fmt "$T1_DATA"
echo
echo "=== Temp 内 _MEI* 残留 === $MEI_COUNT 个(每个约 250MB)"
echo "=== Chrome 缓存子目录 ==="
[ -n "$CHROME" ] && fmt "$CHROME" || echo "无"
echo
echo "=== 系统可清理项 ==="
fmt "$SYS_DATA"
if [ "$TIER" -ge 2 ]; then
  echo
  echo "=== AppData\\Local >300MB ==="; [ -n "$T2_LOCAL" ] && fmt "$T2_LOCAL" || echo "无"
  echo "=== AppData\\Roaming >100MB ==="; [ -n "$T2_ROAM" ] && fmt "$T2_ROAM" || echo "无"
fi
if [ "$TIER" -ge 3 ]; then
  echo
  echo "=== C 盘顶层 ==="; fmt "$T3_DATA"
fi
echo
echo "=== 缓存配置(应指向 D 盘等大容量盘)==="
echo "$CACHE_CFG"
echo "npm_cache=$NPM_CACHE"
