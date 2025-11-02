#!/bin/bash

# 配置使用国内 Git 镜像加速

echo "🇨🇳 配置国内 Git 镜像"
echo "===================="
echo ""

# 使用 GitHub 代理镜像
git config --global url."https://hub.fastgit.xyz/".insteadOf "https://github.com/"
git config --global url."https://github.com.cnpmjs.org/".insteadOf "https://github.com/"

echo "✅ 镜像配置完成！"
echo ""
echo "⚠️  注意：使用镜像可能不稳定"
echo ""
echo "📋 如需取消："
echo "   git config --global --unset url.https://hub.fastgit.xyz/.insteadOf"
echo "   git config --global --unset url.https://github.com.cnpmjs.org/.insteadOf"

