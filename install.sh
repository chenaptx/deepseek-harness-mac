#!/bin/bash
# =============================================================================
# DeepSeek Harness Mac — 一键安装脚本
# 用法:  curl -fsSL https://raw.githubusercontent.com/chenaptx/deepseek-harness-mac/main/install.sh | bash
#
# 为什么需要它: 直接下载 .app 会带上 macOS 的 quarantine(隔离) 属性,
# 首次打开被 Gatekeeper 拦截, 用户被迫"右键→打开"。
# 本脚本下载后自动清除隔离属性, 做到双击即开、无需右键。
# =============================================================================
set -euo pipefail

APP_NAME="DeepSeek Harness.app"
DEST="/Applications/${APP_NAME}"
REPO="chenaptx/deepseek-harness-mac"
ZIP_URL="https://github.com/${REPO}/releases/latest/download/DeepSeek-Harness-Mac-0.1.0.zip"

echo "◆ DeepSeek Harness Mac 一键安装"

# 1. 检查 Node.js ≥ 22
if ! command -v node >/dev/null 2>&1; then
    echo "✗ 未检测到 Node.js。请先安装 Node ≥ 22: https://nodejs.org"
    exit 1
fi
NODE_MAJOR=$(node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)
if [ "$NODE_MAJOR" -lt 22 ]; then
    echo "✗ Node 版本过低 (当前 v$NODE_MAJOR.x, 需要 ≥ 22)。请升级: https://nodejs.org"
    exit 1
fi
echo "✓ Node v$(node -v) 符合要求"

# 2. 下载
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "→ 下载 ${APP_NAME} ..."
curl -fsSL -o "$TMP/app.zip" "$ZIP_URL"
echo "✓ 下载完成 ($(du -h "$TMP/app.zip" | awk '{print $1}'))"

# 3. 解压 + 清除隔离属性 (关键步骤)
echo "→ 解压..."
cd "$TMP"
unzip -q app.zip
if [ ! -d "$APP_NAME" ]; then
    echo "✗ 压缩包内容异常"; exit 1
fi
echo "→ 清除 quarantine 隔离属性..."
xattr -cr "$APP_NAME" 2>/dev/null || true

# 4. 安装到 /Applications
if [ -d "$DEST" ]; then
    echo "→ 检测到旧版本, 先移除..."
    rm -rf "$DEST"   # 这里是覆盖自己下载的旧安装, 非用户数据
fi
if [ -w /Applications ]; then
    cp -R "$APP_NAME" /Applications/
else
    echo "→ 需要管理员权限安装到 /Applications (请输入密码)..."
    sudo cp -R "$APP_NAME" /Applications/
fi
xattr -cr "$DEST" 2>/dev/null || true
echo "✓ 已安装: $DEST"

# 5. 启动
open "$DEST"
echo ""
echo "✅ 完成! 已启动 DeepSeek Harness."
echo "   首次运行会自动拉取 dsh server (需要网络), 之后秒开。"
echo "   卸载: rm -rf '/Applications/${APP_NAME}'"
