#!/usr/bin/env bash
# 本地跑一遍 CI 会做的事（PLAN §8.2 PR 门禁）
#   Scripts/ci-local.sh          # 全跑：lint + 编译 + 测试
#   Scripts/ci-local.sh lint     # 只跑静态检查
#   ZHIWEI_SNAPSHOTS=1 Scripts/ci-local.sh test   # 录制/比对快照
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="${1:-all}"
SIM_NAME="${SIM_NAME:-iPhone 17}"
SIM_OS="${SIM_OS:-26.5}"        # xcodebuild -destination 的 OS 参数只接受纯版本号，不能带 "iOS" 前缀
DERIVED="$PWD/build/DD"

ensure_project() { [ -d ZhiWei.xcodeproj ] || xcodegen generate; }

run_lint() {
  mkdir -p "$DERIVED"
  echo "── swiftformat --lint"
  swiftformat Sources Tests --lint
  echo "── swiftlint"
  swiftlint lint --quiet --config .swiftlint.yml --cache-path "$DERIVED/.swiftlint.cache"
}

run_build() {
  ensure_project
  echo "── build ($SIM_NAME / $SIM_OS)"
  xcodebuild -project ZhiWei.xcodeproj -scheme ZhiWei \
    -destination "platform=iOS Simulator,name=$SIM_NAME,OS=$SIM_OS" \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build \
    | (command -v xcpretty >/dev/null && xcpretty || cat)
}

run_test() {
  ensure_project
  echo "── test"
  xcodebuild test -project ZhiWei.xcodeproj -scheme ZhiWei \
    -destination "platform=iOS Simulator,name=$SIM_NAME,OS=$SIM_OS" \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO \
    ${ZHIWEI_SNAPSHOTS:+-parallel-testing-enabled NO} || {
      echo "测试失败。快照类用例首次需录制基准：ZHIWEI_SNAPSHOTS=1 $0 test" >&2
      exit 2
    }
}

case "$STAGE" in
  lint) run_lint ;;
  build) run_build ;;
  test) run_test ;;
  all) run_lint; run_build; run_test ;;
  *) echo "用法: $0 [lint|build|test|all]" >&2; exit 64 ;;
esac
echo "✅ $STAGE 完成"
