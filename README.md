# 简体注音

iPhone 键盘扩展，按 iOS「繁体中文 → 注音 → 动态调整」的声母页和韵母页排列键位。候选栏直接提供简体单字和词组，词库随应用安装，输入时无需联网或开启「允许完全访问」。

## 安装试用

1. 在 Mac 上用 Xcode 16 或更新版本打开 `Zhuyin.xcodeproj`，选择 `Zhuyin` scheme。
2. 选择 iOS 16 或更新版本的 iPhone 模拟器并运行。真机安装需要为 `Zhuyin` 和 `ZhuyinKeyboard` 两个 target 选择同一个签名团队，并使用该团队注册的 Bundle ID。扩展标识需保留 App 标识作为前缀。
3. 在 iPhone 的「设置 → 通用 → 键盘 → 键盘 → 添加新键盘」启用「简体注音」，回到 App 的试打区或备忘录，长按地球键切换。

Apple 的公开接口让扩展自行绘制键盘并通过文本代理上屏。密码和部分电话字段由系统键盘接管，宿主 App 也可以禁用第三方键盘。[Apple 键盘扩展文档](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard)

## Codemagic 编译

在 Codemagic 连接本工程的 Git 仓库后，选择对应的手动构建流程。

- `ios-device-unsigned` 生成 `Zhuyin-iPhone-Unsigned.ipa`，用于自行签名。签名时需保留并签署包内的键盘扩展。
- `ios-device-signed` 生成可安装到已登记设备的 Ad Hoc IPA。在 Codemagic 的 Code signing identities 中配置 Apple Distribution 证书，以及 `com.wataa2333.zhuyin` 和 `com.wataa2333.zhuyin.keyboard` 各自的 Ad Hoc 描述文件。两个描述文件都需包含目标 iPhone。
- `ios-simulator` 生成 `Zhuyin-Simulator.zip`。解压后可把 `Zhuyin.app` 拖入运行中的 iPhone 模拟器。

真机签名时，App 和键盘扩展可加入 `group.com.wataa2333.zhuyin`，用于自动同步拼音设置。如果自行签名的安装包缺少共享容器权限，在 App 内切换拼音开关后，点「打开键盘同步拼音设置」，再切到「简体注音」键盘。设置会保存在键盘本地。

## 试打

| 操作 | 预期结果 |
| --- | --- |
| 输入 `ㄏㄢˋ ㄗˋ` 并选词 | 上屏「汉字」 |
| 输入 `ㄋㄧˇ ㄏㄠˇ` 并选词 | 上屏「你好」 |
| 输入 `ㄕㄨ`、空格、`ㄖㄨˋ ㄈㄚˇ` 并选词 | 上屏「输入法」 |
| 按 ⇧，输入 `ㄚ` 后按空格 | 在韵母页输入一声并返回声母页 |
| 定调后按退格 | 移除上一个音节的声调并回到韵母页 |
| 输入 `ㄏㄨˋ ㄓㄠˋ`，分两次选择单字「护」「罩」 | 先显示「护ㄓㄠˋ」，最后上屏「护罩」，不残留注音 |
| 输入 `ㄓㄨㄥˋ ㄔㄡˊ`，选择词组或分两次选择「众」「筹」 | 上屏「众筹」，不残留拼音或注音 |

输入声母或介音后自动切到韵母页，介音在两页的键位相同。按空格定一声，其他声调从韵母页输入。定调后可连续输入下一个音节，点选候选上屏。⇧ 可手动切页，便于输入韵母起头的音节。组字中的注音显示在输入框，候选栏提供简体字词，部分字词也会带出表情候选。右侧箭头可展开候选，候选栏和上下留白中的空白处也可点击；触发范围随保存的高度更新，其他候选或按键优先接收自己的触摸。分隔线对齐候选按钮中心，线前预留 8 点；收起时不展示被截半的末尾候选，展开后显示同一组按钮；首行与其余候选使用同一组按钮，展开时换行移动，整个列表可上下滚动，没有单独固定的首行或边缘重复词。Spotlight 没有候选时不显示箭头和分隔线。

拼音标注在简体注音 App 的「键盘设置」中修改；共享容器可用时通过跨进程通知立即更新，无需关闭键盘。缺少共享容器权限时仍使用同步栏。发送等操作键在可用时使用蓝底白字，空内容且宿主要求禁用时显示灰色。按键声音和震动功能及音频资源已移除。

手选多个字或词组时，已选汉字与剩余注音保留在同一个组字范围内；选完后才统一结束组字，避免反复结束、重开组字范围导致宿主把前面的汉字恢复成注音。删除剩余读音会保留并上屏已经选好的汉字。

点 `123` 进入数字页，点 `#+=` 进入符号页，点 `ㄅㄆㄇ` 回到注音。

字符键按下时显示与原键帽相连的放大预览，按键两侧自动内收，预览框首次使用时创建并复用。候选词按下时显示圆角背景框，松开或拖动取消后恢复。

键盘在设备上记录已选字词及其读音，优先显示常选候选。一次连续组字中分段选出的词也可以记入个人词典。多音字的词内声调主要按字音推断，部分常用词有单独标注。

## 词库来源

`Keyboard/Lexicon.sqlite` 收录 939,625 条字词读音，合并雾凇拼音的基础、扩展、腾讯和其他词表，不再按 65,000 条裁剪。保留可转换为逐字注音的中文条目；混合英文、数字等条目暂不纳入。单字合并 Rime 袖珍简化字拼音、雾凇 8105 字表以及 pinyin-data 中所有可转换的汉字读音，用 OpenCC 补充简体形式，也保留可选的原字形，共 44,271 个单字、57,372 条单字读音。生成时优先采用 phrase-pinyin-data 的词组读音，再用 pinyin-data 补充声调；无法确定的声调用零标记，匹配时不强制该声调。固定版本、来源和许可证见 `Keyboard/Notices`，随扩展一起打包。

`Tools/character-coverage.json` 是当前全量核对结果：雾凇 8105 字表的「字表」段含上游增补共 8,121 字，当前缺字为零；固定版本 pinyin-data 中可转换的字音也无遗漏。此前的缺字和缺音明细保存在 `Tools/character-coverage-before.json`。原始拼音数据所含的 44,269 个汉字均有可用读音；仍有 10 条鼻音或合音等特殊读法未映射，对应汉字可用其其他已收录读音输入，详情列在报告中。该基准不代表所有 Unicode 汉字、方言读音或 iOS 字体覆盖。

词库在开发时预先转换、去重并建立音节索引，键盘只读打开 SQLite，按输入音节和声调取有限候选，不在启动时解析完整词表。连接的页缓存设为 512 KiB，文件映射窗口上限为 8 MiB；这不是整个键盘进程的内存上限。旧版 `Lexicon.tsv` 仅在数据库无法打开时作为应急词库。

重建词库时，准备上述固定版本的源文件。

```sh
python3 Tools/build_lexicon.py pinyin_simp.dict.yaml pinyin-data/pinyin.txt TSCharacters.txt rime-ice/cn_dicts/base.dict.yaml phrase-pinyin-data/pinyin.txt --extra-ice rime-ice/cn_dicts/ext.dict.yaml rime-ice/cn_dicts/tencent.dict.yaml rime-ice/cn_dicts/others.dict.yaml --characters rime-ice/cn_dicts/8105.dict.yaml
python3 Tools/audit_character_coverage.py Keyboard/Lexicon.sqlite pinyin-data/pinyin.txt TSCharacters.txt rime-ice/cn_dicts/8105.dict.yaml --output Tools/character-coverage.json
python3 Tools/test_lexicon.py
```

键盘的所有内容高度统一读取 `keyboard-layout.json`，不按宿主高度、安全区或横竖屏自动测量、缩放或补偿。根视图的建议高度和两个 `systemLayoutSizeFitting` 入口均返回同一个固定值。App 的「键盘高度 → 实时预览与调节」可以修改六项尺寸，页面底部直接复用 `KeyboardViewController` 和实际候选列表、按键视图，普通候选和展开候选同步预览；该模式不初始化词库或跨进程设置监听。

点击「保存并应用」直接原子覆盖旧配置，并自动打开实际键盘同步页。切到「简体注音」后，扩展会覆盖本地配置并返回本次请求对应的回执，只有收到回执才显示已接收；App 写入文件不再等同于键盘已应用。高度配置不再从共享容器副本读取，App 和键盘各自只读自己的本地文件，应用时直接覆盖键盘文件；同步不依赖共享容器权限，也不在参数更新时主动收起键盘。配置格式和默认值在 `Shared/KeyboardLayoutConfiguration.swift`，默认内容高度为 258 点；iOS 在扩展之外提供的地球键、麦克风与外部容器仍由系统管理。展开候选时，每行高度、按钮高度和箭头留空区统一使用保存的候选栏高度。App 设置页显示版本号，便于确认安装包。

Spotlight 空闲状态不准备词库和韵母页，首次输入按需打开预建索引。主 App 与扩展可直接离线使用，不需要复制词库到共享容器。

Xcode 的 `CandidatePanelTests` scheme 包含候选切换、高度、分段上屏与词库查询回归测试。Windows 下的 Python 检查验证数据库完整性、覆盖、查询索引和只读访问；它不能替代 iOS 编译和真机手感验证。

冷启动关键路径、开源实现参考和内存回收措施见 `Tools/startup-review.md`。该审查不是 iPhone 实测成绩，后台常驻时间由 iOS 管理。
