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
| 输入 `ㄏㄨˋ ㄓㄠˋ`，分两次选择单字「护」「罩」 | 上屏「护罩」，不残留注音；选择「护」后，只有 `ㄓㄠˋ` 继续组字 |

输入声母或介音后自动切到韵母页，介音在两页的键位相同。按空格定一声，其他声调从韵母页输入。定调后可连续输入下一个音节，点选候选上屏。⇧ 可手动切页，便于输入韵母起头的音节。组字中的注音显示在输入框，候选栏提供简体字词，部分字词也会带出表情候选。右侧箭头可展开候选。拼音标注开关在简体注音 App 的「键盘设置」，重新打开键盘后生效。

点 `123` 进入数字页，点 `#+=` 进入符号页，点 `ㄅㄆㄇ` 回到注音。

字符键按下时会放大预览。开启「允许完全访问」后，可在「简体注音」App 里调节自带按键音的音量和触感强度。音量为零时关闭按键音，iPhone 静音模式也会让按键音静音。

键盘在设备上记录已选字词及其读音，优先显示常选候选。一次连续组字中分段选出的词也可以记入个人词典。多音字的词内声调主要按字音推断，部分常用词有单独标注。

## 词库来源

`Keyboard/Lexicon.tsv` 收录 65,000 条多字词读音，优先收录人工校对的常用短语，其余按雾凇拼音基础词库的权重选取。单字来自 Rime 袖珍简化字拼音，用 OpenCC 单字表规范字形。生成时优先采用 phrase-pinyin-data 的词组读音，再用 pinyin-data 补充声调。固定版本、来源和许可证见 `Keyboard/Notices`，随扩展一起打包。

重建词库时，准备对应版本的五个源文件，最后两个参数分别是雾凇词表和词组拼音表。

```sh
python3 Tools/build_lexicon.py pinyin_simp.dict.yaml pinyin-data/pinyin.txt TSCharacters.txt rime-ice/cn_dicts/base.dict.yaml phrase-pinyin-data/pinyin.txt
```
