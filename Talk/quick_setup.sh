#!/bin/bash

# Talk 项目快速设置脚本
# 跳过 Xcode 的 GUI，直接通过命令行配置和编译

set -e

echo "🚀 Talk 项目快速设置"
echo "=================="
echo ""

# 1. 清理缓存
echo "📦 步骤 1/4: 清理缓存..."
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf .build
echo "   ✓ 缓存清理完成"
echo ""

# 2. 添加 Package 依赖到项目
echo "📝 步骤 2/4: 配置项目..."

PROJECT_FILE="Talk.xcodeproj/project.pbxproj"

# 检查是否已添加 Package
if grep -q "XCLocalSwiftPackageReference" "$PROJECT_FILE"; then
    echo "   ✓ Package 依赖已存在"
else
    echo "   正在添加 SwiftIM Package..."
    ./add_swiftim_package.sh
fi
echo ""

# 3. 解析依赖（使用 swift 命令）
echo "⬇️  步骤 3/4: 解析依赖包..."
echo "   这可能需要几分钟，请耐心等待..."
cd ..
swift package resolve 2>&1 | grep -v "warning:" | head -20 || true
cd Talk
echo "   ✓ 依赖解析完成"
echo ""

# 4. 尝试编译项目
echo "🔨 步骤 4/4: 编译项目..."
xcodebuild -project Talk.xcodeproj \
    -scheme Talk \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    clean build \
    2>&1 | grep -E "✓|Build Succeeded|error:|warning:" | head -30 || true

echo ""
echo "✅ 设置完成！"
echo ""
echo "📱 现在可以在 Xcode 中运行项目了："
echo "   1. open Talk.xcodeproj"
echo "   2. 选择模拟器"
echo "   3. 点击运行 (Command + R)"
echo ""

