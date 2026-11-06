# 键盘启动路径检查

本次是代码路径审查，没有在同一台 iPhone 上测量各输入法的纯冷启动耗时，也没有证明本项目与其他项目速度相同。Windows 的 SQLite 查询耗时不能代替键盘进程启动耗时。

## 开源实现参考

- [Cantoboard 控制器](https://github.com/Cantoboard/Cantoboard/blob/main/CantoboardFramework/Keyboard/KeyboardViewController.swift)：`viewDidLoad` 建立占位视图，`viewWillAppear` 创建输入控制器和视图，`viewDidAppear` 后异步执行引擎准备。它也在首帧前读取设置、创建按键，并不是所有初始化都省略。
- [仓控制器](https://github.com/imfuxiao/Hamster/blob/main/Packages/HamsterKeyboardKit/Sources/Controller/KeyboardInputViewController.swift)：`viewWillAppear` 创建键盘，Rime 初始化通过 detached task 进行。
- [Cantoboard 按键提示框](https://github.com/Cantoboard/Cantoboard/blob/main/CantoboardFramework/Keyboard/View/KeyPopupView.swift)：以键帽宽高构造头部、连接部，并处理边缘方向和高度空间。这里只参考布局方法，没有复制其实现。

## 本项目首帧前保留的工作

- 读取本地拼音标注开关，确保第一帧按键上的标注正确。
- 读取一份很小的固定高度 JSON 配置；内部高度只由该配置决定，不测量宿主高度，不根据横竖屏或安全区补偿高度。之后只通过明确的同步请求覆盖键盘本地配置，不在按键、候选滚动或逐帧布局时读取文件，也不读取旧共享高度副本。
- 建立当前页按键、候选容器和必要约束。
- 读取当前输入框类型、文档标识、是否有文本以及地球键需求，以正确显示布局和发送键状态。

这些工作是首次绘制所需；是否为实际耗时热点，需要设备上的 Time Profiler 或启动追踪验证。

## 已延后的辅助工作

- 反馈音量、触感设置改为显示后在后台读取，初始化期间不会先按默认值发声。
- 设置变化监听在显示后注册，隐藏时移除；下一次显示重新读取最新设置。
- 完全访问权限检查、同步栏设置解析放到显示之后。
- 按键放大预览框在首次按键时才创建，随后复用。
- App 内的高度预览复用键盘控制器的纯展示模式，跳过输入代理读取、引擎预热、音频准备和设置监听；预览代码不会在扩展正常启动时创建额外的键盘视图。
- 非当前键盘页、数据库准备在显示后处理；Spotlight 空闲状态跳过这些预热。
- 词库保持预建索引、只读按需查询；首帧前不读取整份词表、生成索引或复制词库。
- 音频会话准备、样本解码及播放在后台串行队列中执行。

## 生命周期和内存

隐藏键盘时取消预热、偏好读取和退格重复任务，停止声音。收到内存警告时释放预览、音频样本和闲置页面；键盘隐藏时还释放候选按钮缓存，并请求 SQLite 回收未使用的页缓存。

这些措施旨在减少内存压力和重新构建成本，不能保证键盘进程常驻。iOS 扩展生命周期由系统管理，内存限制比普通前台 App 更严格。[Apple 扩展文档](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html)
