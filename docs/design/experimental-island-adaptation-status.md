# 胶囊、展开工作台与显示器适配：实现与验证状态

## 本版范围

继续完善 NookFlow 自有胶囊、展开工作台和无刘海／外接屏适配。系统原生灵动岛接入延后至 macOS 27.3 正式版后另行验证；HealthKit 不纳入本版。

## 当前实现

- 传统宽刘海：保留系统测量的摄像头区域、现有胶囊和多卡片工作台。
- 无刘海／外接屏：启用顶部悬浮胶囊；通用设置可选显示器、水平位置和顶部距离。以显示器 UUID 保存选择，断开时回退主屏；重新连接后恢复选择。距离从可用区域顶部计算，保留菜单栏空间。全屏判断将 AppKit 屏幕坐标转换为 Window Server 坐标。
- 屏幕变化由系统通知驱动；没有新增屏幕轮询。
- 共用的各工作台页面共用一个窗口包络，围绕胶囊中心对齐、顶部固定，沿纵向向下展开。屏幕边缘会对完整包络限位；工作台宽于屏幕时无法保证完整可见。
- “通用 → 实验性适配 → 打开灵动岛模拟窗口”：普通窗口直接使用 IslandRootView、IslandViewModel 和 IslandShellLayout，不另写演示动画。可调胶囊宽高、顶部距离、显示缩放、工作台尺寸，以及宽刘海区域模拟。
- 模拟设置使用单独的临时 UserDefaults 域，关闭窗口时释放视图与任务并清理域，不修改正式设置。模拟模式不启动实时采集、不执行播放控制，也不管理正式胶囊的媒体读取进程；歌词队列预取监听同步停用。模拟拖入只预演接收状态，不导入该拖入文件。文件工作台只读展示实际 FileData，禁用该页操作；可通过模拟窗口的“首页工作台”返回。
- 模拟尺寸是测试参数，不是新机型的真实尺寸。“显示缩放”是画布的布局测试缩放，不替代真实 NSScreen backingScaleFactor 测试。

## 系统原生接口验证

此前接口验证使用 Xcode 27.2（27B52）、macOS SDK 27.2。SDK 的原生 macOS ActivityKit 接口将 ActivityAttributes 和 Activity 标为 macOS unavailable。

最小探针使用 ActivityAttributes + Activity.request，swiftc -typecheck 得到：

```
error: 'ActivityAttributes' is unavailable in macOS
error: 'Activity' is unavailable in macOS
```

该结果只说明 27.2 SDK 的可用性，不代表后续版本不支持。本版按用户决定暂不接入系统灵动岛，不创建覆盖系统区域的透明窗口，也不宣称原生支持。后续需在支持的 SDK 上单独验证状态、操作、展开内容和点击工作台联动。系统外层动画由系统负责。

## 已完成检查

- 应用构建通过（无签名 Debug 构建）。
- 全套 144 项回归检查中通过 142 项；新增模拟播放停用检查通过。剩余两项为此前已有的胶囊源码提取断言与 Debug 签名标识断言，尚未解决。
- 几何检查：负坐标及上下排列外接屏的 Window Server 坐标转换、左右边缘限位、1×／2×缩放、展开中心／顶部锚点、顶部距离下界限位、无刘海分类。
- 面板高度变化不再为了保持底部可见而上移胶囊；内容超出可用高度时仍可能需要滚动或调整布局，不以移动入口补偿。
- 检查代码没有新增周期性任务；模拟窗口释放 hosting view，页面的 existing onDisappear 和 model deinit 负责取消现有任务。

定位检查可重跑：

```
swiftc -parse-as-library Models/NotchGeometryProvider.swift docs/validation/IslandPlacementCheck.swift -o /private/tmp/NookFlowIslandPlacementCheck
/private/tmp/NookFlowIslandPlacementCheck
```

## 尚未验收

- 模拟窗口实际悬停、连续反向、拖入、多卡片布局与窗口关闭后的资源测量。
- 当前复用已有动画状态机，尚未通过逐帧录屏证明快速反向的连续性；不能仅凭代码复用认定动画已验收。
- 真实外接屏热插拔、全屏、隐藏菜单栏、睡眠唤醒及不同缩放。
- 静置、展开与连续操作的 CPU／内存对照。
- 新版机型的系统区域、层级和事件冲突。

这些完成前均为实验性适配。没有向外部用户发送测试版本，也没有生成正式分发安装包。
