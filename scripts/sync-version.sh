#!/bin/bash
# sync-version.sh
# 从 changelogs.md 同步版本号到 project.pbxproj
# MARKETING_VERSION = 主版本.次版本
# CURRENT_PROJECT_VERSION = 主版本.次版本.自增整数
#
# 用法: ./scripts/sync-version.sh [--bump]
#   无参数: 从 changelogs.md 同步基础版本 (如 2.4 / 2.4.0)
#   --bump: 在当前 CURRENT_PROJECT_VERSION 基础上递增末位数字

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG="$PROJECT_ROOT/PhotoTTS/Resources/changelogs.md"
PBXPROJ="$PROJECT_ROOT/PhotoTTS.xcodeproj/project.pbxproj"

# 提取 changelogs.md 最高版本号 (如 2.4.0)
FULL_VERSION=$(grep -m1 '^## v' "$CHANGELOG" | sed 's/## v\([^ ]*\).*/\1/')
if [ -z "$FULL_VERSION" ]; then
    echo "error: Could not extract version from changelogs.md"
    exit 1
fi

# MARKETING_VERSION = 主版本.次版本
MARKETING=$(echo "$FULL_VERSION" | cut -d. -f1,2)

if [ "$1" = "--bump" ]; then
    # 读取当前 CURRENT_PROJECT_VERSION（仅匹配 x.y.z 格式，跳过测试 target 的 = 1）
    CURRENT=$(grep -m1 'CURRENT_PROJECT_VERSION = [0-9][0-9]*\.[0-9]' "$PBXPROJ" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')
    CURRENT_PREFIX=$(echo "$CURRENT" | cut -d. -f1,2)
    CURRENT_NUM=$(echo "$CURRENT" | cut -d. -f3)

    if [ "$CURRENT_PREFIX" = "$MARKETING" ] && [ -n "$CURRENT_NUM" ]; then
        BUILD_NUM=$((CURRENT_NUM + 1))
    else
        BUILD_NUM=0
    fi
else
    # 使用 changelogs 中的修订版号
    BUILD_NUM=$(echo "$FULL_VERSION" | cut -d. -f3)
    [ -z "$BUILD_NUM" ] && BUILD_NUM=0
fi

PROJECT_VERSION="${MARKETING}.${BUILD_NUM}"

# 更新 project.pbxproj 中 PhotoTTS target 的版本号
# 替换 MARKETING_VERSION (仅 PhotoTTS target, 即 com.photoTTS.PhotoTTS 关联的配置)
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = ${MARKETING};/g" "$PBXPROJ"
sed -i '' "/PRODUCT_BUNDLE_IDENTIFIER = com.photoTTS.PhotoTTS;/{
    N
    N
}" "$PBXPROJ"

# 替换所有 target 的 CURRENT_PROJECT_VERSION (PhotoTTS target)
# 精确匹配: 只替换值为 数字.数字.数字 格式的行
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/CURRENT_PROJECT_VERSION = ${PROJECT_VERSION}/g" "$PBXPROJ"

echo "Synced: MARKETING_VERSION=${MARKETING}, CURRENT_PROJECT_VERSION=${PROJECT_VERSION}"
echo "  Source: changelogs.md v${FULL_VERSION}"
