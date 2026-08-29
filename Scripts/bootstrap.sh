#!/usr/bin/env bash
# 从零到可运行（README「快速开始」的实现体）：检查工具链 → 生成工程
set -euo pipefail
cd "$(dirname "$0")/.."

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少 $1：$2" >&2; exit 1; }; }

need xcodegen "brew install xcodegen"
need swiftlint "brew install swiftlint swiftformat"
xcode-select -p | grep -q "Xcode.app" || {
  echo "xcode-select 指向的不是 Xcode.app（当前：$(xcode-select -p)）" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
}

xcodegen generate
git config core.hooksPath .githooks
echo
echo "✅ 工程已生成：ZhiWei.xcodeproj（产物，勿入库）"
echo "   打开：open ZhiWei.xcodeproj"
echo "   命令行构建：Scripts/ci-local.sh build"
echo "   真机需在 Xcode → Settings → Accounts 登录 Apple ID（免费账号 7 天重签，见 PLAN.md §8.3）"
