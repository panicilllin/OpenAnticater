## Install / 安装

Requires macOS 26 or later on Apple Silicon. / 需要 macOS 26 或更高版本，Apple Silicon。

This build is **not notarized by Apple**, so macOS asks you to confirm the first time you open it.
本版本**未经 Apple 公证**，第一次打开时需要手动确认。

1. Download `OpenAnticater-*-arm64.dmg`, open it and drag **OpenAnticater** onto **Applications**.
   下载 `OpenAnticater-*-arm64.dmg`，打开后把 **OpenAnticater** 拖到「Applications」（应用程序）上。
2. Open OpenAnticater from Applications. macOS says it cannot verify the app — click **Done**.
   从「应用程序」里打开 OpenAnticater，系统提示无法验证此 App，点「完成」。
3. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to
   "OpenAnticater was blocked", then confirm with your password.
   打开「系统设置 → 隐私与安全性」，滚动到下方，在「已阻止 OpenAnticater」旁点「仍要打开」，输入密码确认。

You only need to do this once per version. / 每个版本只需要确认一次。

To verify the download / 校验下载文件：

```bash
shasum -a 256 -c OpenAnticater-*-arm64.dmg.sha256
gh attestation verify OpenAnticater-*-arm64.dmg -R panicilllin/OpenAnticater
```

The second command checks that the disk image was built by this repository's GitHub Actions workflow.
第二条命令确认安装包是由本仓库的 GitHub Actions 编译的。

The **Source code** archives below are added by GitHub automatically.
下方的 **Source code** 压缩包是 GitHub 自动附带的源码。

