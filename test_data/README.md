# 本地公开测试样本

用户选择使用 demoinfocs 官方公开测试 Demo。来源为 [cs-demos-2](https://gitlab.com/markus-wa/cs-demos-2)，由 [demoinfocs 回归测试脚本](https://github.com/markus-wa/demoinfocs-golang/blob/v5.2.0/scripts/regression-tests.sh) 使用。

只从 s2.7z 解压 `s2/s2.dem`。固定仓库提交 `df52577f7d01d9dd2172dee6fad48c6d9ced4b22`，下载和哈希验证脚本是 `tools/fetch-test-demo.ps1`。

- 归档：267,908,114 字节。
- 归档 SHA256：`af8227b333cdd881dc9ad49d19d936de04789069ef49b736cd3bf3e6bb37dd43`。
- Demo：39,265,142 字节。
- Demo SHA256：`9051f4690a8a2f1a0d54026685e5f83f1a2aab04574a1cb8735b7413712319a2`。
- 样本地图：de_ancient；源 tick rate：64。
- 本地输出：`public-s2.replay.json`。

Demo、归档、生成的真实 JSON 仅保留在本机并被 .gitignore 排除。来源仓库提供 MIT LICENSE.md；项目没有将样本重新发布。
