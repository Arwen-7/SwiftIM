#!/bin/bash

# SwiftIM SDK 自动配置脚本
# 用于配置 Talk 项目的 SDK 依赖

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_FILE="${SCRIPT_DIR}/Talk.xcodeproj/project.pbxproj"

echo ""
echo "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo "${BLUE}         SwiftIM SDK - Talk 项目配置向导${NC}"
echo "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# 检查项目文件
if [ ! -f "$PROJECT_FILE" ]; then
    echo "${RED}错误：找不到项目文件${NC}"
    echo "请确保在 Talk 目录下运行此脚本"
    exit 1
fi

echo "${GREEN}✓${NC} 找到项目文件"

# 检查 SDK
SDK_DIR="${SCRIPT_DIR}/../Sources/IMSDK"
if [ ! -d "$SDK_DIR" ]; then
    echo "${RED}错误：找不到 SwiftIM SDK${NC}"
    echo "SDK 路径: $SDK_DIR"
    exit 1
fi

echo "${GREEN}✓${NC} 找到 SwiftIM SDK"

# 检查 Package.swift
PACKAGE_FILE="${SCRIPT_DIR}/../Package.swift"
if [ ! -f "$PACKAGE_FILE" ]; then
    echo "${RED}错误：找不到 Package.swift${NC}"
    exit 1
fi

echo "${GREEN}✓${NC} 找到 Package.swift"

echo ""
echo "${YELLOW}配置说明：${NC}"
echo ""
echo "由于 Xcode 17 使用了新的项目格式，SDK 依赖需要手动添加。"
echo "请按照以下步骤操作："
echo ""
echo "${BLUE}步骤 1：在 Xcode 中打开项目${NC}"
echo "  双击 Talk.xcodeproj 或使用命令："
echo "  ${GREEN}open Talk.xcodeproj${NC}"
echo ""
echo "${BLUE}步骤 2：添加本地 Swift Package${NC}"
echo "  1. 选择菜单：File -> Add Package Dependencies..."
echo "  2. 点击左下角的 \"Add Local...\" 按钮"
echo "  3. 导航到并选择 \"IM-iOS-SDK\" 目录"
echo "     路径: ${GREEN}${SCRIPT_DIR}/..${NC}"
echo "  4. 点击 \"Add Package\" 按钮"
echo ""
echo "${BLUE}步骤 3：选择产品${NC}"
echo "  1. 在弹出的对话框中，确保 \"SwiftIM\" 被勾选"
echo "  2. Target 选择 \"Talk\""
echo "  3. 点击 \"Add Package\" 按钮"
echo ""
echo "${BLUE}步骤 4：验证配置${NC}"
echo "  1. 在项目导航器中应该能看到 \"Package Dependencies\" -> \"SwiftIM\""
echo "  2. 编译项目（Command + B）"
echo "  3. 如果编译成功，配置完成！"
echo ""

# 提供快捷命令
echo "${YELLOW}快捷操作：${NC}"
echo ""
echo "  1. ${GREEN}打开 Xcode 项目：${NC}"
echo "     open Talk.xcodeproj"
echo ""
echo "  2. ${GREEN}清理构建缓存：${NC}"
echo "     rm -rf ~/Library/Developer/Xcode/DerivedData"
echo ""
echo "  3. ${GREEN}编译项目（命令行）：${NC}"
echo "     xcodebuild -project Talk.xcodeproj -scheme Talk -destination 'platform=iOS Simulator,name=iPhone 15' clean build"
echo ""

# 询问是否打开 Xcode
echo ""
read -p "是否现在打开 Xcode？(y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "${GREEN}正在打开 Xcode...${NC}"
    open Talk.xcodeproj
    echo ""
    echo "${GREEN}✓${NC} Xcode 已打开，请按照上述步骤添加 SDK 依赖"
else
    echo ""
    echo "${YELLOW}提示：${NC}准备好后，可以手动打开 Xcode 并按照上述步骤操作"
fi

echo ""
echo "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo "${GREEN}更多帮助，请查看：${NC}"
echo "  - README.md"
echo "  - INTEGRATION_GUIDE.md"
echo "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

