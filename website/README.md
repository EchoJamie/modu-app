# MoDu 产品站点

中文单页产品官网，使用原生 HTML、CSS、JavaScript，无第三方依赖、外部字体、分析脚本或后端服务。产品界面仅使用用户提供的真实软件截图；首屏展示纸页明墨，主题区可切换纸页和 GitHub 的明暗外观。产品描述以仓库 README 为依据。

## 本地预览

在仓库根目录运行（需要 Node.js 22 或更新版本；预览服务需要 Python 3）：

```bash
node website/build.mjs
python3 -m http.server 4173 --directory website/dist --bind 127.0.0.1
```

打开 http://127.0.0.1:4173。修改源码后重新执行构建并刷新页面。

构建从 `Config/Info.plist` 读取最低 macOS 版本，复用 `Config/AppIcon-1024.png` 应用图标。只向 `website/dist/` 写入站点公开文件，不会打包 Swift 源码或本地应用产物。

## GitHub → Vercel 自动部署

1. 将站点改动提交并推送到 GitHub。
2. 在 Vercel 中选择 Add New → Project，导入 `EchoJamie/modu-app`。
3. **Root Directory 保持仓库根目录 `.`，不要设置为 `website`**。Framework Preset 为 Other。
4. 根目录 `vercel.json` 已指定构建命令 `node website/build.mjs`、输出目录 `website/dist`，无需安装依赖，也无需环境变量。
5. 选择用于正式站点的生产分支，点击 Deploy；后续推送由 Vercel Git 集成触发部署。

配置参考：https://vercel.com/docs/project-configuration/vercel-json

下载按钮链接到仓库 Releases 列表，不假定已有安装包。正式对外推广前，请在 GitHub Releases 发布 DMG。更新记录指向仓库默认分支的 `changelog.md`；如果调整仓库地址，请同步更新 HTML 中的链接。

站点独立于 macOS 应用，不触发应用版本或构建号调整。

## 站点图片资源

四张截图已按产品主题统一命名并存放于 `assets/product/`：

- `modu-newsprint-light.png`：纸页明墨（首屏主图）。
- `modu-newsprint-dark.png`：纸页暗墨。
- `modu-github-light.png`：GitHub 明墨。
- `modu-github-dark.png`：GitHub 暗墨（主题区默认图）。

保留用户原始 PNG 的画面与分辨率，不改写软件界面、不调整截图配色。构建会将四张图复制到同名公开路径；主题切换替换实际图片，不用 CSS 模拟应用主题。图片按原始比例完整显示，并可点击查看原图。
