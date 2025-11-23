#!/bin/bash

# 生成 Protobuf Swift 代码的脚本
# 使用方法: ./Scripts/generate_proto.sh

set -e

echo "🚀 开始生成 Protobuf Swift 代码..."

# 检查 protoc 是否安装
if ! command -v protoc &> /dev/null; then
    echo "❌ 错误: protoc 未安装"
    echo "请运行: brew install protobuf swift-protobuf"
    exit 1
fi

# 检查 protoc-gen-swift 是否安装
if ! command -v protoc-gen-swift &> /dev/null; then
    echo "❌ 错误: protoc-gen-swift 未安装"
    echo "请运行: brew install swift-protobuf"
    exit 1
fi

# 定义路径
PROTO_DIR="Sources/IMSDK/Core/Protocol"
OUTPUT_DIR="$PROTO_DIR"  # 直接输出到 Protocol 目录

# 编译 proto 文件
echo "📝 编译 IMProtocol.proto..."
protoc \
    --swift_out="$OUTPUT_DIR" \
    --proto_path="$PROTO_DIR" \
    "$PROTO_DIR/IMProtocol.proto"

echo "✅ 生成完成！"
echo "📁 输出目录: $OUTPUT_DIR"
echo ""
echo "生成的文件："
ls -lh "$OUTPUT_DIR"

echo ""
echo "🎉 Protobuf Swift 代码生成成功！"
