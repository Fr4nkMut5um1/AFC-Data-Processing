# GitHub 导入与原始版本

目标：`Fr4nkMut5um1/AFC-Data-Processing`，私有仓库。
源码基准：`c860e5d2e259561147f70e0e932e0b6300bc512e`。

源交付：PIV_r2_current_code.zip，SHA-256：
`192388646aceeb25e6cea55e64d5266ab2e8b482750a99a4a8df3fe1f15f7f9b`。

本仓库根目录对应 ZIP 中的 `PIV_r2_current_code/project/`，与原 Git bundle 的根目录一致。
先读 [START_HERE.md](START_HERE.md)。两个独立 case 位于 `cases/per_case/`。

导入方式：通过 GitHub 插件创建原版文件快照，再添加代码观察层。
GitHub 导入提交会有新的 SHA；不把它冒充原始 c860e5d 提交。
完整原始分批 Git 历史以 `source-history/version_history.bundle` 原样保存，
原包文件清单保存在 `source-history/release_manifest.json`。
需要恢复原始历史时，在另一新目录执行：

```bash
git clone source-history/version_history.bundle original-history
```

科学源码保持原字节。新增观察层位于 `code-intelligence/`，
不成为科学计算的运行依赖。MATLAB 原生静态、动态和正式数据验收仍未执行。
导入代码不表示已部署或运行 MATLAB Actions。
