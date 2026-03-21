# 三省六部 × InkOS — APK 构建完整指南

## 项目结构

```
novel_local/
├── lib/                          # Flutter Dart 源码
│   ├── main.dart                 # 应用入口
│   ├── models/                   # 数据模型
│   ├── providers/                # Riverpod 状态管理
│   ├── core/
│   │   ├── agents/               # 9个AI写作Agent
│   │   ├── db/                   # SQLite数据库
│   │   ├── detection/            # 朱雀文本检测引擎
│   │   ├── llm/                  # LLM客户端（直连API）
│   │   ├── pipeline/             # 三省六部写作管线
│   │   ├── router/               # 路由
│   │   ├── theme/                # 主题（豆包风格）
│   │   └── utils/                # 工具函数
│   ├── platform/                 # 平台服务（通知、防息屏）
│   ├── screens/                  # 12个页面
│   │   ├── splash/               # 启动页 + 引导页
│   │   ├── home/                 # 书库
│   │   ├── writing/              # 写作台（核心）
│   │   ├── chat/                 # AI助手对话
│   │   ├── kanban/               # 任务看板
│   │   ├── world/                # 世界观面板
│   │   ├── hooks/                # 伏笔管理
│   │   ├── characters/           # 角色圣经
│   │   ├── detection/            # 朱雀AI检测
│   │   ├── reader/               # 阅读器
│   │   ├── settings/             # 设置（模型发现）
│   │   ├── style/                # 写作风格
│   │   └── export/               # 导出
│   └── widgets/                  # 公共组件
├── android/                      # Android 原生配置
│   ├── app/
│   │   ├── build.gradle          # 应用构建配置（minSdk 23）
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       ├── kotlin/com/novel/ai/MainActivity.kt
│   │       └── res/
│   ├── build.gradle
│   ├── settings.gradle
│   └── gradle.properties
├── assets/
│   ├── fonts/                    # NotoSerifSC 字体（需手动下载）
│   └── images/                   # 应用图标
├── .github/workflows/
│   └── build_apk.yml             # GitHub Actions 自动构建
├── pubspec.yaml                  # 依赖配置
└── BUILD_GUIDE.md                # 本文件
```

---

## 构建前提条件

### 系统要求
- macOS 10.15+ / Windows 10+ / Ubuntu 20.04+
- 内存 8GB+（编译期峰值使用约 4GB）
- 磁盘 15GB+（Flutter SDK + Android SDK + 构建缓存）

### 必须安装的软件

**1. Flutter SDK 3.24+**

```bash
# macOS/Linux
cd ~
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz
tar xf flutter_linux_3.24.5-stable.tar.xz
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
flutter doctor
```

**2. Android Studio（含 Android SDK）**
- 下载：https://developer.android.com/studio
- 安装后打开 SDK Manager，安装：
  - Android SDK Platform 34
  - Android SDK Build-Tools 34.0.0
  - Android SDK Command-line Tools

**3. Java 17（通常随 Android Studio 安装）**

```bash
java -version  # 应显示 17.x
```

---

## 方法一：命令行直接构建（推荐）

```bash
# 1. 进入项目目录
cd novel_local

# 2. 下载字体文件（必须！否则构建失败）
mkdir -p assets/fonts
# 方式A: 从 Google Fonts 下载
curl -L "https://fonts.gstatic.com/s/notoserifsc/v22/H4chBXePl9DZ0Xe7gG9cyOj7mgq0SBnEQAUC.ttf" \
     -o assets/fonts/NotoSerifSC-Regular.ttf
curl -L "https://fonts.gstatic.com/s/notoserifsc/v22/H4c8BXePl9DZ0Xe7gG9cyOj7oqC9SjYf.ttf" \
     -o assets/fonts/NotoSerifSC-Bold.ttf
cp assets/fonts/NotoSerifSC-Regular.ttf assets/fonts/NotoSerifSC-SemiBold.ttf

# 3. 配置 Android SDK 路径
cat > android/local.properties << EOF
sdk.dir=$HOME/Android/Sdk
flutter.sdk=$HOME/flutter
flutter.versionName=1.0.0
flutter.versionCode=1
flutter.buildMode=debug
EOF

# 4. 安装依赖
flutter pub get

# 5. 构建 Debug APK（快，无需签名，推荐先用这个）
flutter build apk --debug \
  --target-platform android-arm64 \
  --dart-define=APP_ENV=production

# APK 输出位置：
# build/app/outputs/flutter-apk/app-debug.apk

# 6. 构建 Release APK（需要签名，适合正式发布）
flutter build apk --release \
  --target-platform android-arm64 \
  --obfuscate \
  --split-debug-info=build/debug-info

# APK 输出位置：
# build/app/outputs/flutter-apk/app-release.apk
```

---

## 方法二：Docker 一键构建（无需本地环境）

```bash
# 确保已安装 Docker
docker --version

# 一键构建（约 10-15 分钟，首次需下载镜像）
bash build_apk.sh

# APK 输出到 ./dist/novel_ai_arm64_debug.apk
```

---

## 方法三：GitHub Actions（最简单，推荐新手）

**步骤：**

1. **创建 GitHub 账号**（免费）：https://github.com

2. **创建新仓库**：点击右上角 `+` → `New repository`，名称填 `novel-ai`

3. **上传代码**：
   ```bash
   cd novel_local
   git init
   git add .
   git commit -m "initial commit"
   git remote add origin https://github.com/你的用户名/novel-ai.git
   git push -u origin main
   ```

4. **等待自动构建**：
   - 打开仓库页面 → 点击 `Actions` 选项卡
   - 可以看到 `Build APK` 任务正在运行
   - 约 15 分钟后变为绿色 ✅

5. **下载 APK**：
   - 点击已完成的 workflow run
   - 在底部 `Artifacts` 区域找到 `novel-ai-apk-xxxxx`
   - 点击下载 zip，解压得到 APK

---

## 字体文件处理（重要！）

`pubspec.yaml` 声明了 NotoSerifSC 字体，构建时必须存在：

```yaml
fonts:
  - family: NotoSerifSC
    fonts:
      - asset: assets/fonts/NotoSerifSC-Regular.ttf
      - asset: assets/fonts/NotoSerifSC-Bold.ttf
      - asset: assets/fonts/NotoSerifSC-SemiBold.ttf
```

**如果没有字体文件，有两种处理方式：**

**方式A**：下载字体（推荐）
- 访问 https://fonts.google.com/noto/specimen/Noto+Serif+SC
- 下载并放到 `assets/fonts/`

**方式B**：临时去掉字体声明（最快）
```yaml
# 删除 pubspec.yaml 中的 fonts 节
# 代码中的 fontFamily: 'NotoSerifSC' 会自动回退到系统字体
```

---

## 安装 APK 到手机

### 方式一：ADB 安装（需开启开发者模式）

```bash
# 手机开启：设置 → 开发者选项 → USB调试
# 连接 USB 后：
adb devices  # 看到设备列表
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### 方式二：直接传文件安装

1. 将 APK 文件传到手机（微信/QQ/文件管理/数据线）
2. 手机端：设置 → 安全 → 允许未知来源安装（或直接点 APK 文件）
3. 点击安装

### 方式三：二维码安装（最方便）

上传 APK 到任意网盘（阿里云盘/百度网盘）生成下载链接，手机扫码下载安装

---

## 常见错误解决

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `SDK location not found` | 未设置 Android SDK 路径 | 创建 `android/local.properties` |
| `Font file not found` | 缺少字体文件 | 下载字体或去掉 pubspec.yaml 字体声明 |
| `Gradle build failed` | Java 版本不对 | 确保使用 Java 17 |
| `pub get failed` | 网络问题 | 设置 Flutter 镜像：见下方 |
| `minSdkVersion error` | 某个依赖要求更高 SDK | 检查 build.gradle minSdk |

**Flutter 国内镜像（加速 pub get）：**
```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
```

---

## APK 文件说明

| 文件名 | 说明 | 适用设备 |
|--------|------|---------|
| `app-arm64-v8a-debug.apk` | 调试版，64位 | 2017年后的大多数手机 |
| `app-armeabi-v7a-debug.apk` | 调试版，32位 | 老旧手机 |
| `app-release.apk` | 正式版，需签名 | 发布到应用商店用 |

**推荐安装**：`app-arm64-v8a-debug.apk`（除非手机特别老）

---

## 首次使用

1. 打开 App → 三步引导页
2. 选择 AI 供应商（推荐 **DeepSeek**，国内直连，最便宜）
3. 填写 API Key（从供应商官网获取，免费或充少量费用）
4. 点「搜索可用模型」自动发现模型列表
5. 保存 → 进入书库 → 创建第一本书 → 开始创作

**获取 DeepSeek API Key：**
https://platform.deepseek.com/api_keys（国内，注册免费，按用量极低费用）
