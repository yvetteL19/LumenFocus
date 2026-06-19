# Ambient Sound Assets

Drop three royalty-free loopable `.m4a` files in this directory:

| 文件名 | 内容 | 时长建议 |
|---|---|---|
| `rain.m4a` | 轻雨白噪音 | 30s–2min（无缝循环） |
| `whitenoise.m4a` | 粉红/白噪音 | 30s（无缝循环） |
| `forest.m4a` | 林间鸟声 / 树叶 | 1–2min |

## 要求

- **必须无缝循环**：首尾过渡不能有"咔哒"或音量跳变。可以用 Audacity 的 Cross-fade 处理
- **采样率**：44.1 kHz / 16-bit 即可
- **响度**：peak ≤ -3 dB；RMS ≤ -18 dB，避免太响打扰用户
- **许可证**：CC0 / 公共领域，或可商用授权（保留授权证明在 `docs/licenses/`）

## 推荐资源

- Freesound.org（筛选 CC0）
- Zapsplat（免费账号，注明出处）
- Pixabay Sounds

## 文件缺失时的行为

`AmbientSoundManager` 找不到对应资源时只会写一条 warning 日志后静默无操作。不会崩溃，也不会影响其它休息体验。
