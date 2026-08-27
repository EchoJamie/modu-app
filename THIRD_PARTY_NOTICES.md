# Third-party notices

墨读的构建和交付包含以下固定版本第三方组件。版本、修订、来源和许可证文件均由仓库记录；`scripts/verify_third_party.sh` 会在交付构建前校验依赖锁定与随包脚本摘要。

| Component | Version / revision | License | Source and bundled notice |
| --- | --- | --- | --- |
| swift-markdown | 0.7.3 / `7d9a5ce307528578dfa777d505496bd5f544ad94` | Apache-2.0 | https://github.com/swiftlang/swift-markdown.git; `Package.resolved`; build checkout `swift-markdown/LICENSE.txt` |
| swift-cmark | 0.8.0 / `924936d0427cb25a61169739a7660230bffa6ea6` | BSD/MIT notices | https://github.com/swiftlang/swift-cmark.git; `Package.resolved`; build checkout `swift-cmark/COPYING` |
| Mermaid | 11.16.1 | MIT | https://github.com/mermaid-js/mermaid; `Sources/MoDu/Resources/Mermaid/ORIGIN.md` and `LICENSE.txt` |
| Highlight.js | 11.12.0 | BSD-3-Clause | https://github.com/highlightjs/cdn-release; `Sources/MoDu/Resources/Highlighter/ORIGIN.md` and `LICENSE.txt` |

`toml.min.js` 是墨读维护的 Highlight.js 语言注册代码，不属于上游分发文件。正式 `.app` 会同时包含本清单、Swift 依赖许可证以及随包前端资源的许可证。
