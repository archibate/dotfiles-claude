---
name: zhlint
description: >
  中文排版规范（全角标点、中英文空格）+ zhlint 校验工具。Use whenever writing or editing formal Chinese
  document content — Chinese markdown docs, README 中文版, blog posts, WeChat articles, translation
  output, announcements, tutorials — or when the user mentions 排版, 全角/半角, punctuation or spacing
  issues in Chinese text. Apply even if the user doesn't explicitly ask for typography checking.
---

# 中文排版（zhlint）

中文语境下严格遵守：

1. 标点全部用全角：，。？！：；、（）“”……——中文句内禁用半角 `, . ? ! : ; ( ) "`
2. 中英文之间、中文与数字之间各留一个空格；英文/数字紧邻全角标点时不留空格
3. 纯英文句子仍按英文规范用半角标点

示例（严格模仿其标点与空格）：

> 调用 API 时传入 3 个参数，结果存为 result.json（约 2 MB）。这样对吗？对，完全符合“中文排版”规范。

## 校验工具

写完后用 zhlint 校验（必须用相对路径 —— 绝对路径会触发 zhlint 的 ignore 模块崩溃）：

```bash
cd <文件所在目录>
npx -y zhlint --config ~/.claude/skills/zhlint/assets/zhlintrc.json foo.md        # 校验，exit 1 = 有错误
npx -y zhlint --config ~/.claude/skills/zhlint/assets/zhlintrc.json foo.md --fix  # 原地自动修复
```

- `--config` 指向本 skill 自带的配置，作用是把括号也转成全角（zhlint 默认保留半角括号加空格，与规则 1 冲突）。
- `--fix` 直接改写文件，绕过 Edit 的 diff 跟踪；修复后重新 Read 文件再继续编辑。
- zhlint 是安全网，不是作者：个别情形它查不出（如数字与英文单位之间的空格 “2 MB”）。先按上述规则写对，再跑校验，直到零错误。
