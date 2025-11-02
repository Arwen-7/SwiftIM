# SwiftIM SDK 集成指南

本文档详细说明如何将 SwiftIM SDK 集成到 Talk 项目中。

## 方法一：通过 Xcode 界面添加（推荐）

### 步骤 1：打开项目

在 Xcode 中打开 `Talk.xcodeproj`。

### 步骤 2：添加本地 Swift Package

1. 在项目导航器中选择 `Talk` 项目（蓝色图标）
2. 在编辑器区域，选择 `Talk` target
3. 切换到 "General" 标签页
4. 向下滚动找到 "Frameworks, Libraries, and Embedded Content" 部分

### 步骤 3：添加 Package 依赖

**方式 A：通过 Package Dependencies**

1. 选择项目（不是 target）
2. 切换到 "Package Dependencies" 标签页
3. 点击 "+" 按钮
4. 点击 "Add Local..." 按钮
5. 导航到 `IM-iOS-SDK` 目录（Talk 项目的父目录）
6. 选择整个 `IM-iOS-SDK` 文件夹
7. 点击 "Add Package"

**方式 B：通过菜单**

1. 选择菜单 File -> Add Package Dependencies...
2. 点击左下角的 "Add Local..." 按钮
3. 选择 `IM-iOS-SDK` 目录
4. 点击 "Add Package"

### 步骤 4：选择产品

在添加 Package 后，会弹出产品选择对话框：

1. 确保 "SwiftIM" 被勾选
2. Target 选择 "Talk"
3. 点击 "Add Package"

### 步骤 5：验证

1. 在项目导航器中，你应该能看到 "Package Dependencies" 下有 SwiftIM
2. 编译项目 (Command + B)，确保没有错误
3. 如果成功，就可以在代码中 `import SwiftIM` 了

## 方法二：手动修改 project.pbxproj

如果方法一不成功，可以尝试手动编辑项目文件。

### 步骤 1：关闭 Xcode

确保 Xcode 已完全关闭。

### 步骤 2：编辑 project.pbxproj

用文本编辑器打开：
```
Talk.xcodeproj/project.pbxproj
```

### 步骤 3：添加 Package Reference

在 `PBXProject` section 中，找到 `projectRoot = "";` 这一行，在它下面添加：

```
packageReferences = (
    A80AE16D2EB74XXX000E526D /* XCLocalSwiftPackageReference "../" */,
);
```

### 步骤 4：添加 Package Reference Object

在文件末尾，`rootObject` 之前，添加：

```
/* Begin XCLocalSwiftPackageReference section */
    A80AE16D2EB74XXX000E526D /* XCLocalSwiftPackageReference "../" */ = {
        isa = XCLocalSwiftPackageReference;
        relativePath = ..;
    };
/* End XCLocalSwiftPackageReference section */
```

### 步骤 5：添加 Package Product Dependency

在 `PBXNativeTarget` section 的 `Talk` target 中，找到 `packageProductDependencies` 行，修改为：

```
packageProductDependencies = (
    A80AE16E2EB74XXX000E526D /* SwiftIM */,
);
```

然后在文件末尾添加：

```
/* Begin XCSwiftPackageProductDependency section */
    A80AE16E2EB74XXX000E526D /* SwiftIM */ = {
        isa = XCSwiftPackageProductDependency;
        package = A80AE16D2EB74XXX000E526D /* XCLocalSwiftPackageReference "../" */;
        productName = SwiftIM;
    };
/* End XCSwiftPackageProductDependency section */
```

**注意**：将 `A80AE16D2EB74XXX000E526D` 和 `A80AE16E2EB74XXX000E526D` 替换为唯一的 UUID。可以使用命令生成：

```bash
uuidgen | tr '[:lower:]' '[:upper:]' | sed 's/-//g' | cut -c 1-24
```

### 步骤 6：重新打开 Xcode

打开 `Talk.xcodeproj`，Xcode 会自动识别 Package 依赖。

## 方法三：使用脚本自动配置

我们提供了一个自动配置脚本：

```bash
cd Talk
./configure_sdk.sh
```

如果脚本不存在，创建它：

```bash
#!/bin/bash

# 自动配置 SwiftIM SDK 依赖

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_FILE="${SCRIPT_DIR}/Talk.xcodeproj/project.pbxproj"

echo "正在配置 Talk 项目..."

# 检查项目文件是否存在
if [ ! -f "$PROJECT_FILE" ]; then
    echo "错误：找不到项目文件"
    exit 1
fi

# 生成唯一 UUID
UUID1=$(uuidgen | tr '[:lower:]' '[:upper:]' | sed 's/-//g' | cut -c 1-24)
UUID2=$(uuidgen | tr '[:lower:]' '[:upper:]' | sed 's/-//g' | cut -c 1-24)

echo "生成的 UUID:"
echo "  Package Reference: $UUID1"
echo "  Product Dependency: $UUID2"

# 提示用户手动配置
echo ""
echo "请按照以下步骤手动配置："
echo "1. 在 Xcode 中打开 Talk.xcodeproj"
echo "2. 选择 File -> Add Package Dependencies..."
echo "3. 点击 'Add Local...'"
echo "4. 选择 IM-iOS-SDK 目录"
echo "5. 确保选中 SwiftIM 产品"
echo "6. 点击 'Add Package'"
echo ""
echo "配置完成后，运行项目即可！"
```

## 验证集成

集成完成后，验证以下几点：

### 1. 编译测试

```bash
xcodebuild -project Talk.xcodeproj -scheme Talk -destination 'platform=iOS Simulator,name=iPhone 15' clean build
```

### 2. 代码导入测试

在任意 Swift 文件中添加：

```swift
import SwiftIM

// 测试 SDK 是否可用
let client = IMClient.shared
```

如果没有编译错误，说明集成成功。

### 3. 运行测试

1. 在 Xcode 中选择模拟器
2. 点击运行 (Command + R)
3. 应用应该能正常启动并显示对话列表页

## 常见问题排查

### 问题 1：找不到 SwiftIM 模块

**症状**：
```
No such module 'SwiftIM'
```

**解决方法**：
1. 检查 Package Dependencies 是否正确添加
2. Clean Build Folder (Shift + Command + K)
3. 重启 Xcode
4. 删除 DerivedData：
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```

### 问题 2：Package 无法解析

**症状**：
```
Package resolution failed
```

**解决方法**：
1. 检查 Package.swift 文件是否存在于 `IM-iOS-SDK` 目录
2. 检查 Package.swift 的平台版本是否兼容
3. 尝试更新 Package：
   - File -> Packages -> Update to Latest Package Versions

### 问题 3：依赖项冲突

**症状**：
```
Multiple packages declare a target named 'XXX'
```

**解决方法**：
1. 检查是否重复添加了 Package
2. 在 Package Dependencies 中删除重复的引用
3. Clean 并重新 Build

### 问题 4：Xcode 卡死

**解决方法**：
1. 强制退出 Xcode
2. 删除 DerivedData
3. 删除项目的 xcuserdata
4. 重新打开项目

## 需要帮助？

如果按照上述步骤仍无法成功集成，请：

1. 检查 Xcode 版本（需要 15.0+）
2. 检查 Swift 版本（需要 5.9+）
3. 查看详细的编译错误日志
4. 提交 Issue 并附上错误信息

