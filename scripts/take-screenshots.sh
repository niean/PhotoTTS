#!/bin/bash
# App Store 截图自动化脚本
# 用法:
#   ./scripts/take-screenshots.sh                 # 运行全部设备
#   ./scripts/take-screenshots.sh -d iPhone_14_Plus  # 指定单个设备
#   ./scripts/take-screenshots.sh -d iPhone_14_Plus -d iPad_Pro_13_M5  # 指定多个设备
#
# 适配设备（App Store 必需尺寸）:
#   - iPhone 14 Plus (6.5")    : 1284 x 2778
#   - iPad Pro 13-inch (M5)    : 2064 x 2752
#
# 截图内容：由 ScreenshotUITests 控制
#
# 工作原理:
#   1. 在每个模拟器上运行 ScreenshotUITests
#   2. 用 xcresulttool export attachments 提取截图
#   3. 重命名为友好名称，保存到 locals/distribution/screenshots/<设备名>/

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/locals/distribution/screenshots"
RESULT_DIR="${OUTPUT_DIR}/.build_results"
PROJECT="${PROJECT_ROOT}/PhotoTTS.xcodeproj"
TEST_CLASS="ScreenshotUITests"
TEST_METHOD="testCaptureAllScreenshots"

# 设备列表："显示名 | 模拟器名称"
ALL_DEVICES=(
    "iPhone_14_Plus|iPhone 14 Plus"
    "iPad_Pro_13_M5|iPad Pro 13-inch (M5)"
)

# 解析命令行参数
SELECTED_DEVICES=()
show_help() {
    echo "用法：$0 [-d 设备名] ..."
    echo ""
    echo "选项:"
    echo "  -d  指定设备名称（可多次使用），可选值:"
    for entry in "${ALL_DEVICES[@]}"; do
        IFS='|' read -r label sim <<< "${entry}"
        echo "      ${label}"
    done
    echo "  -h  显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                              # 运行全部设备"
    echo "  $0 -d iPhone_14_Plus            # 仅运行 iPhone 14 Plus"
    echo "  $0 -d iPhone_14_Plus -d iPad_Pro_13_M5  # 运行指定多个设备"
}

while getopts "d:h" opt; do
    case $opt in
        d)
            SELECTED_DEVICES+=("$OPTARG")
            ;;
        h)
            show_help
            exit 0
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

# 如果没有指定设备，使用全部设备
if [ ${#SELECTED_DEVICES[@]} -eq 0 ]; then
    for entry in "${ALL_DEVICES[@]}"; do
        IFS='|' read -r label _ <<< "${entry}"
        SELECTED_DEVICES+=("$label")
    done
fi

# 过滤出要处理的设备
DEVICES=()
for selected in "${SELECTED_DEVICES[@]}"; do
    found=false
    for entry in "${ALL_DEVICES[@]}"; do
        IFS='|' read -r label sim <<< "${entry}"
        if [ "$label" = "$selected" ]; then
            DEVICES+=("${entry}")
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo "错误：未知设备 '${selected}'"
        echo "可用设备:"
        for entry in "${ALL_DEVICES[@]}"; do
            IFS='|' read -r label _ <<< "${entry}"
            echo "  - ${label}"
        done
        exit 1
    fi
done

rename_screenshots() {
    local device_dir="$1"
    python3 -c "
import json, os, shutil
outdir = '${device_dir}'
manifest_path = os.path.join(outdir, 'manifest.json')
if not os.path.exists(manifest_path):
    print('  manifest.json not found, skip rename')
    exit(0)
with open(manifest_path) as f:
    manifest = json.load(f)
for te in manifest:
    for att in te.get('attachments', []):
        exp = att.get('exportedFileName', '')
        sug = att.get('suggestedHumanReadableName', '')
        if exp and sug:
            name = sug.split('_Clone_')[0]
            if not name.endswith('.png'): name += '.png'
            src = os.path.join(outdir, exp)
            dst = os.path.join(outdir, name)
            if os.path.exists(src):
                shutil.move(src, dst)
                print(f'  {exp} -> {name}')
os.remove(manifest_path)
"
}

main() {
    echo "=== App Store 截图自动化 ==="
    echo "项目: ${PROJECT}"
    echo "输出: ${OUTPUT_DIR}"
    echo ""

    # 清理已有截图子目录（保留脚本自身）
    for device_entry in "${DEVICES[@]}"; do
        IFS='|' read -r dl _ <<< "${device_entry}"
        rm -rf "${OUTPUT_DIR}/${dl}"
    done
    rm -rf "${RESULT_DIR}"
    mkdir -p "${RESULT_DIR}"

    for device_entry in "${DEVICES[@]}"; do
        IFS='|' read -r device_label simulator_name <<< "${device_entry}"
        local device_dir="${OUTPUT_DIR}/${device_label}"
        mkdir -p "${device_dir}"

        echo "=========================================="
        echo "设备: ${simulator_name} (${device_label})"
        echo "=========================================="

        # 1. 查找模拟器 UDID
        local udid
        udid=$(xcrun simctl list devices available | grep "${simulator_name}" | head -1 | grep -oE '[A-F0-9-]{36}')
        if [ -z "${udid}" ]; then
            echo "  错误: 未找到模拟器 '${simulator_name}'，跳过"
            continue
        fi
        echo "  UDID: ${udid}"

        # 2. 启动模拟器
        echo "  启动模拟器..."
        xcrun simctl boot "${udid}" 2>/dev/null || true
        sleep 3

        # 3. 运行 UI 测试（含截图）
        local result_path="${RESULT_DIR}/${device_label}.xcresult"
        rm -rf "${result_path}"
        echo "  构建并运行截图测试..."

        xcodebuild test \
            -project "${PROJECT}" \
            -scheme "PhotoTTSUITests" \
            -destination "platform=iOS Simulator,id=${udid},arch=arm64" \
            -only-testing:"PhotoTTSUITests/${TEST_CLASS}/${TEST_METHOD}" \
            -resultBundlePath "${result_path}" \
            -quiet \
            2>&1 | tail -3 || {
                echo "  警告: 测试执行可能有错误"
            }

        # 4. 提取截图
        if [ -d "${result_path}" ]; then
            echo "  提取截图..."
            xcrun xcresulttool export attachments \
                --path "${result_path}" \
                --output-path "${device_dir}" 2>&1 | grep -E "^Exported|^File:" || true

            echo "  重命名截图..."
            rename_screenshots "${device_dir}"
        else
            echo "  警告: 未生成 xcresult"
        fi

        # 5. 关闭模拟器
        echo "  关闭模拟器..."
        xcrun simctl shutdown "${udid}" 2>/dev/null || true

        # 6. 验证尺寸
        echo "  截图尺寸:"
        for f in "${device_dir}"/*.png; do
            [ -f "$f" ] || continue
            local w h
            w=$(sips -g pixelWidth "$f" 2>/dev/null | tail -1 | awk '{print $2}')
            h=$(sips -g pixelHeight "$f" 2>/dev/null | tail -1 | awk '{print $2}')
            echo "    $(basename "$f"): ${w}x${h}"
        done

        echo "  完成: ${device_label}"
        echo ""
    done

    # 清理临时文件
    echo "--- 清理临时构建结果 ---"
    rm -rf "${RESULT_DIR}"

    # 汇总
    echo ""
    echo "=== 截图完成 ==="
    echo "输出目录: ${OUTPUT_DIR}"
}

main "$@"
