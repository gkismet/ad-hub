# ad-hub —— 团队统一广告模块

每个人的项目各自开发，广告统一管理：

```
ad-hub/
├─ skill/gk-adhub/         给 Claude Code / Codex 用的 skill：教它按团队规范接广告
├─ config/apps/            每个项目一份广告配置（广告位、单元 ID、开关、频控）
├─ unity/Assets/AdHub/     Unity 模块（源码，同步进项目）
├─ flutter/                Flutter 包 ad_hub（git 依赖引用）
└─ tools/                  校验配置、同步 Unity 模块、安装 skill
```

支持：AppLovin MAX（默认，AdMob 走 MAX 下的 Google bidding）/ AdMob 直连；插屏、激励、横幅、开屏；配置统一维护、随包发布；频控；统一埋点事件（含收益）。

## 同事第一次用
1. clone 本仓库（路径里不要有中文）：`git clone https://github.com/gkismet/ad-hub.git`
2. 安装 skill（自动识别本机装了 Claude Code 还是 Codex，两个都有就都装）：
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\install_skill.ps1
   ```
   只装一边：加 `-Target claude` 或 `-Target codex`。装到的位置：
   - Claude Code：`%USERPROFILE%\.claude\skills\gk-adhub`
   - Codex：`%USERPROFILE%\.agents\skills\gk-adhub`（Codex 里看不到的话加 `-Copy` 重装）
3. 重开 Claude Code / Codex，在自己的项目里说"接一下广告"/"加个复活激励视频"即可。AI 会先列广告位建议表，你确认后才动手。

## 核心规则
- 代码里只写广告位名字，ID 和开关在 `config/apps/<app>.json`
- 改配置 → `tools\sync_config.ps1 -App <app> -Project <项目>`（自动校验再拷进项目）→ 提交 → 出包
- 不在项目里改 AdHub 源码；要改就改这个仓库，升 `VERSION`，写 `CHANGELOG.md`

## 负责人待办
- [ ] 如团队共用一个 MAX 账号，把 SDK Key 填进各项目配置的 `maxSdkKey`

## 配置
正本在 `config/apps/<app>.json`，随包发布，不依赖服务器。改配置要重新出包才对玩家生效。
```powershell
powershell -ExecutionPolicy Bypass -File tools\sync_config.ps1 -App my_app -Project D:\Games\MyGame
```
自动识别 Unity（→ `Assets/Resources/adhub_config.json`）/ Flutter（→ `assets/adhub_config.json`）。
