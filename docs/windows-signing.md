# Windows 发布者签名

公开版本 v0.9.1-beta.1 及 v0.9.2-beta.1 没有 Authenticode 签名。`AppPublisher=huaxiangqiming` 只是安装器显示字段，不构成 Windows 的发布者身份验证。校验文件 SHA-256 能检测下载内容是否一致，也不能替代代码签名。

## 外部前提

需要由受 Windows 信任的 CA 签发的代码签名证书，或已完成身份审核的云签名服务。私人自签证书不用于公开分发；不要求用户关闭 SmartScreen 或安装开发者自己的根证书。申请身份、地区资格、费用和账号需要由项目所有者确定，工具不能替代身份审核。

本机当前用户和计算机证书库未发现代码签名证书，也未找到 Windows SDK SignTool；因此尚未生成可验证发布者的新安装包。正式签名和安装后的签名验收仍待外部前提完成。

## 已接入的证书库方式

安装 Windows SDK SignTool，并通过证书供应商的安全设备/客户端使证书可从 Windows `My` 证书库访问。私钥不进入仓库，不在聊天或命令中传 PFX 密码。

```powershell
./tools/package_windows.ps1 -RequireSignature `
  -CertificateThumbprint '<证书指纹>' `
  -CertificateStore CurrentUser `
  -SignTool '<Windows SDK>/signtool.exe'
```

流程：先验证指定证书存在、含可用私钥、用途为代码签名、未过期且信任链有效；再编译并签署主程序、Parser 和地图工具；Inno Setup 调用相同签名工具签署安装器及卸载器。SignTool 使用 SHA-256 文件摘要、RFC 3161 时间戳和 SHA-256 时间戳摘要。每次签名后验证发布者指纹、签名状态与时间戳；任何失败中止，ZIP 和最终校验文件在签名完成后才生成。

证书链在当前电脑有效不自动证明其面向所有公网用户受信任；证书必须来自面向公开分发的可信签发机构。第三方依赖保留上游文件，不冒充其发布者。

云签名方式需在项目所有者确定服务后接入对应提供商；当前脚本不会冒称已支持任何云账户。

## 本地界面预览

默认打包必须配置签名。仅在明确传入下面选项时生成未签名包：

```powershell
./tools/package_windows.ps1 -AllowUnsignedPreview
```

输出到 `dist/previews/<version>/`，文件名带 `unsigned-preview`，包内附 `SIGNING-STATUS.txt`。这是未签名预览，不能称为“已验证发布者”。经用户明确授权可以作为标注了未签名状态的预发布分发，不得描述成已完成签名的正式包。

安装验收可运行：

```powershell
./tools/test_windows_installer.ps1 -Setup '<正式签名安装包>' -RequireSignature
```

该模式检查安装包，以及安装后的主程序、Parser、地图工具、卸载器均有有效签名、匹配发布者指纹和时间戳。未签名预览验收应省略 `-RequireSignature`，并明确记录该限制。

## 发布者验证与 SmartScreen

有效签名提供可验证的发布者身份；SmartScreen 同时评估文件及发布者信誉，因此新文件或新发布者仍可能出现信誉提示。不能承诺购买证书后立即消除所有 Windows 警告。

依据：[Microsoft SmartScreen 说明](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)、[SignTool 参数](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)、[Inno Setup SignTool](https://jrsoftware.org/ishelp/topic_setup_signtool.htm)、[微软 Artifact Signing 身份验证](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart)。
