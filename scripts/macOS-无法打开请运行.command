#!/bin/bash
#
# Lumen for macOS —— “无法打开 / 已损坏 / 无法验证开发者” 修复脚本
#
# 原因：Lumen 未做 Apple 付费公证签名，会被 macOS 的 Gatekeeper 拦截。
# 本脚本会移除隔离标记并做本地(ad-hoc)签名，之后即可正常打开。
# 用法：双击本文件运行（若提示无法打开本脚本，右键 -> 打开）。
#
set -u

echo "=================================================="
echo "  Lumen macOS 修复工具"
echo "=================================================="
echo ""

find_app() {
  local candidates=(
    "/Applications/Lumen.app"
    "$HOME/Applications/Lumen.app"
    "$HOME/Downloads/Lumen.app"
    "$HOME/Desktop/Lumen.app"
    "$(cd "$(dirname "$0")" 2>/dev/null && pwd)/Lumen.app"
  )
  local c
  for c in "${candidates[@]}"; do
    if [ -d "$c" ]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

APP="$(find_app)"

if [ -z "${APP:-}" ]; then
  echo "未找到 Lumen.app。"
  echo "请先把 Lumen 拖进「应用程序」文件夹，"
  echo "或把本脚本与 Lumen.app 放在同一目录后再运行。"
  echo ""
  read -n 1 -s -r -p "按任意键退出…"
  echo ""
  exit 1
fi

echo "找到应用：$APP"
echo ""
echo "正在修复（移除隔离标记 + 本地签名），过程中可能需要输入开机密码…"
echo ""

# 移除隔离标记（优先普通权限，失败再用 sudo）
xattr -dr com.apple.quarantine "$APP" 2>/dev/null \
  || sudo xattr -dr com.apple.quarantine "$APP" 2>/dev/null \
  || true

# 本地 ad-hoc 重新签名，解决“已损坏”提示
codesign --force --deep --sign - "$APP" 2>/dev/null \
  || sudo codesign --force --deep --sign - "$APP" 2>/dev/null \
  || true

echo "修复完成！现在可以正常打开 Lumen 了。"
echo "（若仍提示，请在「系统设置 -> 隐私与安全性」点击「仍要打开」。）"
echo ""
read -n 1 -s -r -p "按任意键退出…"
echo ""
