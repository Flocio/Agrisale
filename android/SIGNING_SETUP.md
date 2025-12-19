# Android 签名配置说明

## 问题说明

Android 应用覆盖安装需要满足两个条件：
1. **构建号（versionCode）必须递增**
2. **签名必须完全匹配**

如果签名不匹配，即使构建号递增，Android 也会拒绝安装并显示 "App not installed"。

## 解决方案

使用统一的 release keystore，确保本地构建和 GitHub Actions 构建使用相同的签名。

---

## 第 1 步：生成 Release Keystore（只做一次）

在项目根目录执行：

```bash
keytool -genkeypair \
  -alias agrisale \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -keystore android/app/agrisale-release.jks
```

**重要提示**：
- 记住输入的密码（storePassword 和 keyPassword）
- 这个 keystore 文件是应用的"身份证"，一旦丢失无法恢复
- 如果已经对外发布过 APK，必须继续使用旧的 keystore

---

## 第 2 步：配置本地签名

1. 复制模板文件：
```bash
cp android/key.properties.example android/key.properties
```

2. 编辑 `android/key.properties`，填写真实信息：
```properties
storePassword=你的store密码
keyPassword=你的key密码
keyAlias=agrisale
storeFile=agrisale-release.jks
```

3. 确保 `agrisale-release.jks` 文件在 `android/app/` 目录下

4. 验证本地构建：
```bash
flutter build apk --release
```

---

## 第 3 步：配置 GitHub Actions

### 3.1 将 keystore 转换为 base64

在项目根目录执行：

```bash
base64 android/app/agrisale-release.jks > agrisale-release.jks.base64
```

### 3.2 添加 GitHub Secrets

前往：**仓库 → Settings → Secrets and variables → Actions → New repository secret**

添加以下 4 个 Secrets：

| Secret 名                | 内容                    |
| ----------------------- | --------------------- |
| `ANDROID_KEYSTORE_BASE64` | base64 文件内容（整个文件内容） |
| `ANDROID_STORE_PASSWORD`  | storePassword         |
| `ANDROID_KEY_PASSWORD`    | keyPassword           |
| `ANDROID_KEY_ALIAS`       | agrisale              |

### 3.3 验证 workflow

GitHub Actions workflow 已经配置好，会在构建前自动：
1. 从 Secrets 恢复 keystore 文件
2. 创建 key.properties 文件

---

## 第 4 步：验证签名一致性

### 本地构建验证签名：

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

### GitHub Actions 构建验证：

1. 从 GitHub Releases 下载 APK
2. 执行相同的命令验证签名
3. 对比 SHA-1 / SHA-256，应该完全一致

---

## 重要提醒

1. **keystore 一旦生成，永远不要换** - 否则已安装用户无法升级
2. **不要把 keystore 提交到 git** - 已添加到 .gitignore
3. **备份 keystore 和密码** - 丢失后无法恢复
4. **GitHub Secrets 也要备份** - 建议保存在安全的密码管理器中

---

## 故障排查

### 如果仍然无法覆盖安装：

1. 检查构建号是否递增（pubspec.yaml 中的 `+` 后面的数字）
2. 验证签名是否一致（使用 `apksigner verify`）
3. 如果签名不一致，检查：
   - GitHub Secrets 是否正确配置
   - keystore 文件是否正确恢复
   - key.properties 是否正确创建

---

## 当前配置状态

- ✅ `build.gradle.kts` 已配置支持 keystore
- ✅ GitHub Actions workflow 已配置自动恢复 keystore
- ✅ `.gitignore` 已配置忽略 keystore 文件
- ⚠️ 需要您手动生成 keystore 并配置 GitHub Secrets

