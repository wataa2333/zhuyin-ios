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

## 试打

| 操作 | 预期结果 |
| --- | --- |
| 输入 `ㄏㄢˋ ㄗˋ` 并选词 | 上屏「汉字」 |
| 输入 `ㄋㄧˇ ㄏㄠˇ` 并选词 | 上屏「你好」 |
| 输入 `ㄕㄨ`、空格、`ㄖㄨˋ ㄈㄚˇ` 并选词 | 上屏「输入法」 |
| 按 ⇧，输入 `ㄚ` 后按空格 | 在韵母页输入一声并返回声母页 |
| 定调后按退格 | 移除上一个音节的声调并回到韵母页 |

输入声母或介音后自动切到韵母页，介音在两页的键位相同。按空格定一声，其他声调从韵母页输入。定调后可连续输入下一个音节，点选候选上屏。⇧ 可手动切页，便于输入韵母起头的音节。待选注音显示在键盘候选栏，选字后写入宿主 App。

这是首版，使用静态词频和词典匹配。多音字的词内声调主要按字音推断，部分常用词有单独标注。长输入在没有整词候选时可逐段选择，候选排序和系统注音词库会有差异。

## 词库来源

`Keyboard/Lexicon.tsv` 从 Rime 袖珍简化字拼音生成，用 pinyin-data 补充声调并使用 OpenCC 的单字表规范字形。固定版本和许可证见 `Keyboard/Notices`，这些文件随扩展一起打包。

重建词库时，准备对应版本的三个源文件并运行：

```sh
python3 Tools/build_lexicon.py /path/to/pinyin_simp.dict.yaml /path/to/pinyin.txt /path/to/TSCharacters.txt
```
