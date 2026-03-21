#!/usr/bin/env bash
# 三省六部 × InkOS — 一键构建 APK
# 需要：Docker 已安装（无需本地 Flutter/Android SDK）

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/dist"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "  ⚔️  三省六部 × InkOS — APK 构建"
echo "  ================================"
echo ""

# 检查 Docker
if ! command -v docker &>/dev/null; then
  echo "❌ 未找到 Docker，请先安装：https://docs.docker.com/get-docker/"
  exit 1
fi

echo "📦 拉取 Flutter 构建镜像..."
docker pull ghcr.io/cirruslabs/flutter:3.24.5 2>&1 | tail -3

echo ""
echo "🔨 开始构建 APK..."
docker run --rm \
  -v "$SCRIPT_DIR":/app \
  -v "$OUTPUT_DIR":/output \
  -w /app \
  ghcr.io/cirruslabs/flutter:3.24.5 \
  bash -c "
    set -e
    echo '→ flutter pub get'
    flutter pub get
    
    echo '→ 构建 debug APK (arm64)'
    flutter build apk --debug \
      --target-platform android-arm64 \
      --dart-define=APP_VERSION=1.0.0
    
    echo '→ 复制到输出目录'
    cp build/app/outputs/flutter-apk/app-debug.apk /output/novel_ai_arm64_debug.apk
    
    echo '→ APK 大小:'
    ls -lh /output/novel_ai_arm64_debug.apk
  "

echo ""
echo "✅ 构建完成！"
echo ""
echo "APK 文件："
ls -lh "$OUTPUT_DIR"/*.apk 2>/dev/null
echo ""
echo "安装方式："
echo "  1. USB 调试：adb install $OUTPUT_DIR/novel_ai_arm64_debug.apk"
echo "  2. 手动安装：将 APK 传到手机，开启「未知来源」后安装"
echo ""
