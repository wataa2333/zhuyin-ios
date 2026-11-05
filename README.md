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

输入声母或介音后自动切到韵母页，介音在两页的键位相同。按空格定一声，其他声调从韵母页输入。定调后可连续输入下一个音节，点选候选上屏。⇧ 可手动切页，便于输入韵母起头的音节。组字中的注音显示在输入框，候选栏提供简体字词，部分字词也会带出表情候选。右侧 64 × 44 点的箭头区域可展开候选，附近横向 24 点、纵向 14 点的留白也可点击，其他候选或按键优先接收自己的触摸；首行与其余候选使用同一组按钮，展开时换行移动，整个列表可上下滚动，没有单独固定的首行或边缘重复词。Spotlight 没有候选时不显示箭头和分隔线。

拼音标注、按键音量和触感强度在简体注音 App 的「键盘设置」中修改；共享容器可用时通过跨进程通知立即更新，无需关闭键盘。缺少共享容器权限时仍使用同步栏。发送等操作键在可用时使用蓝底白字，空内容且宿主要求禁用时显示灰色。音频初始化、解码和播放使用后台串行队列，过时的按键音会跳过，避免阻塞触摸。

手选多个字或词组时，已选汉字与剩余注音保留在同一个组字范围内；选完后才统一结束组字，避免反复结束、重开组字范围导致宿主把前面的汉字恢复成注音。删除剩余读音会保留并上屏已经选好的汉字。

点 `123` 进入数字页，点 `#+=` 进入符号页，点 `ㄅㄆㄇ` 回到注音。

字符键按下时会放大预览。开启「允许完全访问」后，可在「简体注音」App 里调节自带按键音的音量和触感强度。音量为零时关闭按键音，iPhone 静音模式也会让按键音静音。

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

键盘尺寸集中在 `KeyboardLayoutConfiguration.swift`，首次显示前即使用固定尺寸，横竖屏变化时才切换配置。Spotlight 空闲状态不准备词库、韵母页和音效，首次输入按需打开预建索引。主 App 与扩展可直接离线使用，不需要复制词库到共享容器。

Xcode 的 `CandidatePanelTests` scheme 包含候选切换、高度、分段上屏与词库查询回归测试。Windows 下的 Python 检查验证数据库完整性、覆盖、查询索引和只读访问；它不能替代 iOS 编译和真机手感验证。
