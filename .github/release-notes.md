## Install / 安装

Requires macOS 26 or later on Apple Silicon. / 需要 macOS 26 或更高版本，Apple Silicon。

This build is **not notarized by Apple**, so macOS asks you to confirm the first time you open it.
本版本**未经 Apple 公证**，第一次打开时需要手动确认。

1. Download `OpenAnticater-*-arm64.zip`, unzip it and move **OpenAnticater** to **Applications**.
   下载 `OpenAnticater-*-arm64.zip`，解压后把 **OpenAnticater** 拖进「应用程序」。
2. Open it. macOS says it cannot verify the app — click **Done**.
   打开它，系统提示无法验证此 App，点「完成」。
3. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to
   "OpenAnticater was blocked", then confirm with your password.
   打开「系统设置 → 隐私与安全性」，滚动到下方，在「已阻止 OpenAnticater」旁点「仍要打开」，输入密码确认。

You only need to do this once per version. / 每个版本只需要确认一次。

To verify the download / 校验下载文件：

```bash
shasum -a 256 -c OpenAnticater-*-arm64.zip.sha256
gh attestation verify OpenAnticater-*-arm64.zip -R panicilllin/OpenAnticater
```

The second command checks that the zip was built by this repository's GitHub Actions workflow.
第二条命令确认 zip 是由本仓库的 GitHub Actions 编译的。

