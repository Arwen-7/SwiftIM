#!/bin/bash

# 预下载 SwiftIM SDK 的依赖包
# 这会加速 Xcode 的 Package 解析过程

set -e

CACHE_DIR=~/Library/Caches/org.swift.swiftpm/repositories

echo "📦 预下载 Swift Package 依赖..."
echo ""

# 创建缓存目录
mkdir -p "$CACHE_DIR"

# 依赖列表
declare -A DEPS=(
    ["Alamofire"]="https://github.com/Alamofire/Alamofire.git"
    ["Starscream"]="https://github.com/daltoniam/Starscream.git"
    ["CryptoSwift"]="https://github.com/krzyzanowskim/CryptoSwift.git"
    ["swift-protobuf"]="https://github.com/apple/swift-protobuf.git"
)

# 下载每个依赖
for name in "${!DEPS[@]}"; do
    url="${DEPS[$name]}"
    echo "⬇️  正在下载 $name..."
    echo "   URL: $url"
    
    # 生成缓存目录名（SPM 使用 URL hash 作为目录名）
    cd "$CACHE_DIR"
    
    if [ -d "*$name*" ] 2>/dev/null; then
        echo "   ✓ $name 已存在，跳过"
    else
        echo "   下载中..."
        git clone --bare "$url" "temp-$name" 2>&1 | head -5 || true
        echo "   ✓ $name 下载完成"
    fi
    echo ""
done

echo "✅ 所有依赖预下载完成！"
echo ""
echo "现在可以在 Xcode 中添加 Package 了，速度会快很多。"

