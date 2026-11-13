# 私域 CRM iOS 版

本目录只包含 iOS SwiftUI 应用源码。工程由仓库根目录的 `project.yml` 通过 XcodeGen 生成，最低系统版本为 iOS 15，发布方式为 TrollStore 免签 IPA。

应用数据运行时保存在 iOS App 沙盒 Documents 中，不随源码或构建产物上传到 GitHub。新安装的软件默认没有客户和订单数据，可在应用内自行录入或导入备份。

本目录与 `CRMWindows/` 独立构建，iOS 工作流只读取本目录和根目录 `project.yml`。
