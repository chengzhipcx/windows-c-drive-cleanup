#!/usr/bin/env bash
# Windows C 盘空间扫描(Git Bash 环境运行)
# 用法: bash scan_c_drive.sh [用户名]
#   默认用户名: Administrator
# 输出: 磁盘总览 / 误判项排除 / 用户热点 / _MEI* 残留 / 系统可清理项 / 现有缓存配置

set -u
# 避免中文输出在 GBK 控制台乱码
chcp.com 65001 >/dev/null 2>&1
USER_NAME="${1:-Administrator}"
U="/c/Users/$USER_NAME"

if [ ! -d "$U" ]; then
  echo "错误: 用户目录不存在: $U" >&2
  exit 1
fi

echo "=== 磁盘总览 ==="
powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk | ForEach-Object { '{0} 总:{1:N0}GB 已用:{2:N0}GB 剩余:{3:N0}GB' -f \$_.DeviceID, (\$_.Size/1GB), ((\$_.Size-\$_.FreeSpace)/1GB), (\$_.FreeSpace/1GB) }"

echo
echo "=== 误判项排除(pagefile / vhdx)==="
ls -la /c/ 2>/dev/null | grep -iE "pagefile|hiberfil|swapfile" | awk '{print $NF, "约", $5/1024/1024/1024, "GB"}'
find "$U" -maxdepth 5 \( -name "*.vhdx" -o -name "*.vhd" \) 2>/dev/null | head -5 || true

echo
echo "=== 用户热点目录 ==="
du -s -B1 \
  "$U/AppData/Local/Temp" \
  "$U/AppData/Local/npm-cache" \
  "$U/AppData/Local/Yarn" \
  "$U/AppData/Local/uv" \
  "$U/AppData/Local/ms-playwright" \
  "$U/AppData/Local/Google" \
  "$U/AppData/Local/Microsoft" \
  "$U/AppData/Local/Programs" \
  "$U/AppData/Roaming" \
  "$U/Downloads" \
  "$U/Documents" \
  "$U/.bun" \
  2>/dev/null | sort -rn | awk '{printf "%8.2f GB  %s\n", $1/1073741824, $2}'

echo
echo "=== Temp 内 _MEI* PyInstaller 残留 ==="
MEI_COUNT=$(find "$U/AppData/Local/Temp" -maxdepth 1 -name "_MEI*" 2>/dev/null | wc -l)
echo "残留目录数: $MEI_COUNT(每个约 0.25GB)"

echo
echo "=== VS Code 扩展安装包缓存 ==="
du -s -B1 "$U/AppData/Roaming/Code/CachedExtensionVSIXs" 2>/dev/null | awk '{printf "%8.2f GB  %s\n", $1/1073741824, $2}'

echo
echo "=== 系统级可清理项 ==="
du -s -B1 \
  /c/Windows/SoftwareDistribution/Download \
  /c/Windows/Temp \
  /c/Windows/Installer \
  '/c/$Recycle.Bin' \
  2>/dev/null | awk '{printf "%8.2f GB  %s\n", $1/1073741824, $2}'

echo
echo "=== 现有缓存配置(已迁移则应指向 D 盘等)==="
powershell -NoProfile -Command "'UV_CACHE_DIR: ' + [Environment]::GetEnvironmentVariable('UV_CACHE_DIR','User'); 'YARN_CACHE_FOLDER: ' + [Environment]::GetEnvironmentVariable('YARN_CACHE_FOLDER','User'); 'BUN_INSTALL: ' + [Environment]::GetEnvironmentVariable('BUN_INSTALL','User')" 2>/dev/null
echo "npm cache: $(npm config get cache 2>/dev/null)"
echo "yarn cache dir: $(yarn cache dir 2>/dev/null)"
