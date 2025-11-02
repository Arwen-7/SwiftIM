#!/bin/bash

# 自动为 Talk 项目添加 SwiftIM Package 依赖
# 适用于 Xcode 15+ 的新项目格式

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_FILE="${SCRIPT_DIR}/Talk.xcodeproj/project.pbxproj"

echo "🔧 自动添加 SwiftIM Package 依赖到 Talk 项目"
echo ""

# 检查项目文件
if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ 错误：找不到项目文件"
    exit 1
fi

echo "✓ 找到项目文件: Talk.xcodeproj"

# 备份项目文件
cp "$PROJECT_FILE" "${PROJECT_FILE}.backup"
echo "✓ 已备份项目文件"

# 生成唯一 ID
generate_id() {
    echo "A80AE1$(openssl rand -hex 3 | tr '[:lower:]' '[:upper:]')2EB74CD3000E526D"
}

PACKAGE_REF_ID=$(generate_id)
PACKAGE_PROD_ID=$(generate_id)

echo ""
echo "生成的 ID:"
echo "  Package Reference: $PACKAGE_REF_ID"
echo "  Package Product:   $PACKAGE_PROD_ID"
echo ""

# 检查是否已添加
if grep -q "XCLocalSwiftPackageReference" "$PROJECT_FILE"; then
    echo "⚠️  项目中已存在 Package 引用"
    echo "   如需重新配置，请先删除现有引用"
    exit 0
fi

# 临时文件
TEMP_FILE="${PROJECT_FILE}.temp"
cp "$PROJECT_FILE" "$TEMP_FILE"

# 1. 在 PBXProject section 中添加 packageReferences
echo "📝 步骤 1: 添加 Package References..."
sed -i '' "/projectRoot = \"\";/a\\
			packageReferences = (\\
				$PACKAGE_REF_ID \\/\\* XCLocalSwiftPackageReference \\\"..\\\" \\*\\/,\\
			);
" "$TEMP_FILE"

# 2. 在 PBXNativeTarget section 中添加 packageProductDependencies  
echo "📝 步骤 2: 添加 Package Product Dependencies..."
sed -i '' "s/packageProductDependencies = (/packageProductDependencies = (\\
				$PACKAGE_PROD_ID \\/\\* SwiftIM \\*\\/,/" "$TEMP_FILE"

# 3. 在文件末尾添加 Package Reference section
echo "📝 步骤 3: 添加 Package Reference Section..."
sed -i '' "/End XCConfigurationList section/a\\
\\
\\/\\* Begin XCLocalSwiftPackageReference section \\*\\/\\
		$PACKAGE_REF_ID \\/\\* XCLocalSwiftPackageReference \\\"..\\\" \\*\\/ = {\\
			isa = XCLocalSwiftPackageReference;\\
			relativePath = ..;\\
		};\\
\\/\\* End XCLocalSwiftPackageReference section \\*\\/
" "$TEMP_FILE"

# 4. 在文件末尾添加 Package Product Dependency section
echo "📝 步骤 4: 添加 Package Product Dependency Section..."
sed -i '' "/End XCLocalSwiftPackageReference section/a\\
\\
\\/\\* Begin XCSwiftPackageProductDependency section \\*\\/\\
		$PACKAGE_PROD_ID \\/\\* SwiftIM \\*\\/ = {\\
			isa = XCSwiftPackageProductDependency;\\
			package = $PACKAGE_REF_ID \\/\\* XCLocalSwiftPackageReference \\\"..\\\" \\*\\/;\\
			productName = SwiftIM;\\
		};\\
\\/\\* End XCSwiftPackageProductDependency section \\*\\/
" "$TEMP_FILE"

# 替换原文件
mv "$TEMP_FILE" "$PROJECT_FILE"

echo ""
echo "✅ SwiftIM Package 依赖添加成功！"
echo ""
echo "📋 后续步骤："
echo "   1. 在 Xcode 中打开项目：open Talk.xcodeproj"
echo "   2. Xcode 会自动识别 Package 依赖"
echo "   3. 等待依赖解析完成（可能需要几分钟）"
echo "   4. 编译项目：Command + B"
echo ""
echo "💡 如果出现问题："
echo "   - 恢复备份：cp Talk.xcodeproj/project.pbxproj.backup Talk.xcodeproj/project.pbxproj"
echo "   - 清理缓存：rm -rf ~/Library/Developer/Xcode/DerivedData"
echo ""

