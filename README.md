# 私域 CRM

本仓库只保存应用源码、构建配置和公开说明，不包含任何实际客户、订单、顾问、手机号、地址、快递单号或本机数据库。

## 平台目录

- `CRMApp/`：iOS 版 SwiftUI 源码。
- `CRMWindows/`：Windows 版 WinForms 源码。
- `project.yml`：iOS 版 XcodeGen 工程配置。
- `.github/workflows/build_ipa.yml`：iOS IPA 构建。
- `.github/workflows/build_crm_windows.yml`：Windows EXE 构建。

两个平台的界面与构建流程彼此独立，但数据模型保持兼容，可通过应用内的明文 JSON 备份功能迁移数据。

## 数据隐私

- iOS 数据仅保存在 App 沙盒 Documents 中。
- Windows 数据仅保存在 `%LOCALAPPDATA%\PrivateCRMWindows\` 中。
- 本地数据库、备份、Excel/CSV 文件及构建产物均被 `.gitignore` 排除。
- 新用户下载或自行构建后得到的是空数据库，需要自行导入或录入客户资料。

## 构建

### iOS

使用 XcodeGen 根据 `project.yml` 生成工程，再通过 Xcode 或 GitHub Actions 构建 TrollStore IPA。

### Windows

在 Windows PowerShell 中运行：

```powershell
.\CRMWindows\build.ps1
```

生成文件位于 `CRMWindows\dist\PrivateCRM-Windows.exe`。
