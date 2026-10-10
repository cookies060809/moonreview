# Git Hooks

## Pre-commit Hook

提交前做两件事：跑 `moon check`，以及拦住不该进公开仓库的内容 —— `PROPOSAL.md`（申报书，里面有手机号）和长得像密钥、手机号的字符串。`.gitignore` 已经排除了这些文件，这道闸是防止 `git add -f` 之类的误操作。

### Usage Instructions

To use this pre-commit hook:

1. Make the hook executable if it isn't already:
   ```bash
   chmod +x .githooks/pre-commit
   ```

2. Configure Git to use the hooks in the .githooks directory:
   ```bash
   git config core.hooksPath .githooks
   ```

3. The hook will automatically run when you execute `git commit`
