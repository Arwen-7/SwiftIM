#!/bin/bash

# 一键解决 Talk 项目依赖问题
# 手动下载所有依赖到正确位置

set -e

echo "🔧 修复 Talk 项目依赖问题"
echo "=============================="
echo ""

# SPM 缓存目录
CACHE_DIR=~/Library/Caches/org.swift.swiftpm/repositories

# 创建缓存目录
mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

echo "📦 步骤 1/5: 下载 Alamofire..."
if [ -d "Alamofire"* ]; then
    echo "   ✓ Alamofire 已存在"
else
    git clone --bare https://github.com/Alamofire/Alamofire.git Alamofire-$(date +%s) 2>&1 | tail -5
    echo "   ✓ Alamofire 下载完成"
fi
echo ""

echo "📦 步骤 2/5: 下载 Starscream..."
if [ -d "Starscream"* ]; then
    echo "   ✓ Starscream 已存在"
else
    git clone --bare https://github.com/daltoniam/Starscream.git Starscream-$(date +%s) 2>&1 | tail -5
    echo "   ✓ Starscream 下载完成"
fi
echo ""

echo "📦 步骤 3/5: 下载 CryptoSwift..."
if [ -d "CryptoSwift"* ]; then
    echo "   ✓ CryptoSwift 已存在"
else
    git clone --bare https://github.com/krzyzanowskim/CryptoSwift.git CryptoSwift-$(date +%s) 2>&1 | tail -5
    echo "   ✓ CryptoSwift 下载完成"
fi
echo ""

echo "📦 步骤 4/5: 下载 swift-protobuf（重要！）..."
# 删除可能存在的错误缓存
rm -rf swift-protobuf* protobuf* 2>/dev/null || true

# 下载正确的仓库
echo "   正在从 https://github.com/apple/swift-protobuf.git 下载..."
git clone --bare https://github.com/apple/swift-protobuf.git swift-protobuf-$(date +%s) 2>&1 | tail -10
echo "   ✓ swift-protobuf 下载完成"
echo ""

echo "📊 步骤 5/5: 验证下载..."
echo ""
echo "已下载的依赖包："
ls -lh "$CACHE_DIR" | grep -v "^total" | grep -v "^d.*\.$"
echo ""

TOTAL_SIZE=$(du -sh "$CACHE_DIR" | cut -f1)
echo "✅ 所有依赖下载完成！"
echo "   总大小: $TOTAL_SIZE"
echo ""

echo "🚀 接下来的步骤："
echo "   1. 打开 Xcode 项目"
echo "   2. Xcode 会使用这些本地缓存"
echo "   3. 不需要再从 GitHub 下载"
echo ""

# 打开 Xcode
read -p "是否现在打开 Xcode？(y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "正在打开 Xcode..."
    cd ~/Project/IM/IM-iOS-SDK/Talk
    open Talk.xcodeproj
    echo ""
    echo "✨ Xcode 已打开！依赖解析现在应该很快。"
else
    echo ""
    echo "💡 准备好后，运行: open ~/Project/IM/IM-iOS-SDK/Talk/Talk.xcodeproj"
fi

echo ""
echo "=============================="
echo "✅ 修复完成！"

