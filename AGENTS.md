# AGENTS.md

<INSTRUCTIONS>
- 始终使用中文回复用户。

## 版本规则

- 应用版本号采用 `x.y.z` 格式。
- 修复缺陷或优化现有功能时，只递增 `z`。
- 新增功能或产品特性时，递增 `y`，并将 `z` 归零。
- `x` 的变更由开发者明确确定；未经开发者要求，不得自行递增 `x`。
- 调整应用版本时，必须同步更新 `Config/Info.plist` 中的 `CFBundleShortVersionString`，并在 `changelog.md` 中新增对应版本记录，不得把新改动追加到已经交付的旧版本记录中。
- `CFBundleVersion` 作为构建号，每次生成新的交付版本时保持单调递增。
</INSTRUCTIONS>
