# darwin-arm64 Runtime

此目录是 AgentMac 的本地内置 runtime 生成目录。

提交到 GitHub：

- `README.md`
- `manifest.json`

不提交到 GitHub：

- `node/`
- `pi/node_modules/`

生成或更新本地 runtime：

```bash
node scripts/update-vendored-runtime.mjs --pi-repo /path/to/pi-main --platform darwin-arm64
```

Xcode 构建只复制这里已经生成好的 runtime，不执行 Pi build 或 `npm install`。
