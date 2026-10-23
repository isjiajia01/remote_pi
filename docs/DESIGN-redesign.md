---
name: Perch
version: "redesign-2026-10-23"
basis: perch/minimal 5eea568 (Flutter iOS 伴侣)
colors:            # 复用 app_colors.dart；仅 working-text 为新增
  light: {bg: "#F4F2EC", surface: "#FFFFFF", surface2: "#ECEAE3", hairline: "#DAD7CE", ink: "#1A1C1E", ink2: "#5E6166", ink3: "#85888D", accent: "#1D5FC4", onAccent: "#FFFFFF", working: "#A65D00", workingSoft: "#FBEBD3", online: "#2F7D4F", error: "#C2302B", errorSoft: "#FBE3E1", userBubble: "#E3E9F6", codeInk: "#2B3A55", workingText: "#9A5500"}
  dark:  {bg: "#0F1012", surface: "#1A1C1F", surface2: "#24272B", hairline: "#2E3135", ink: "#ECEAE4", ink2: "#9DA0A6", ink3: "#6C7075", accent: "#7FAEFF", onAccent: "#0F1012", working: "#F2A93B", workingSoft: "#33270F", online: "#5FC98A", error: "#FF6B61", errorSoft: "#3A1B19", userBubble: "#22314F", codeInk: "#B9C8E6", workingText: "#F2A93B"}
typography:        # 系统 SF/PingFang + JetBrains Mono（已内置），均随 Text size × Dynamic Type 缩放
  largeTitle: {size: 34, weight: 700, tracking: -0.4}
  title2: {size: 22, weight: 600}
  headline: {size: 17, weight: 600}
  body: {size: 17}
  chatBody: {size: 16, line: 24}
  subhead: {size: 15}
  footnote: {size: 13}
  caption: {size: 12, weight: 500}
  mono: {family: JetBrainsMono, size: 13}
rounded: {card: 20, control: 14, sheet: 28, bubble: 20, bubbleTail: 6, pill: 999}
spacing: {s1: 4, s2: 8, s3: 12, s4: 16, s5: 20, s6: 24, s8: 32, target: 44, pageMargin: 20}
motion: {fast: 120ms, base: 220ms, slow: 320ms, ease: "cubic-bezier(.2,.8,.2,1)"}
components:
  primaryButton: {height: 52, radius: 14, bg: accent, fg: onAccent}
  secondaryButton: {height: 48, radius: 14, bg: surface, border: hairline, fg: accent}
  ghostButton: {height: 44, fg: accent}
  iconButton: {size: 44}
  segmentedItem: {height: 44}
  agentRow: {minHeight: 76}
  modelChip: {height: 44, radius: pill}
---

# Perch 重设计（方向：栖木上的状态点）

产物：`index.html`（高保真可点击原型，单文件、无网络依赖）、`icon/`（App icon）、`shots/`（浏览器自测截图，仅示例数据）。
用户原截图含真实主机名和 relay 域名，未复制进本目录，原型全部使用示例数据（Studio MacBook Pro / studio-mbp.tail1a2b3.ts.net）。

## Overview

Perch 只做一件事：在手机上看自己 Mac 上的 Pi agent 是否在线、是否在干活、用的什么模型，读流式回复，必要时停止或补一句。设计原则：
1. 状态第一：每个 agent 的“在线 / 工作中 / 离线 / 最后已知”用 **形状 + 文字 + 颜色** 三重编码，不靠颜色单独表达。
2. 机器是容器，agent 是内容：同一台 Mac 的 agents 放进一张卡，卡内一条“栖木竖线”串起状态点；线实 = 机器在线，线虚 = 离线或 relay 失联。这是唯一的视觉记忆点，别处保持克制。
3. 少一层是一层：去掉底部 Tab（只有 2 项），设置收进首页右上齿轮；Relay 不单列“新页面里再选一次”，首次引导 3 步压成 2 步。
4. 信任边界说实话：全程不出现“E2E / 端到端加密”的肯定表述；Relay 页和首次引导明确写 TLS 传输保护、非端到端、relay 运营方可读（与 README / PROTOCOL.md §398 一致）。
5. 不复活已关闭能力：无 mesh / daemon / cron / Control / 审批 / push / Timeline 入口。

## 现有截图的可用性问题（IMG_6924–6926）

首页（Agents）
- 分组标题 `10.14_SLIP` 与卡片标题 `10.14_Slip` 重复；每组只有一行时 “0 working · 1 online” 也是噪声。
- 同一个 hostname 以灰色 mono 胶囊在每行重复（两行一模一样），占掉最显眼的第二行；真正区分 agent 的信息（路径、最近一句）反而没有。
- `标准` 胶囊无标签、`think: low` 是 mono 术语，且和 `Online` 三个元素同高度并排，中英混排、不知道是模型还是什么；长模型名没有截断策略。
- 右上 “—” / “35m” 无含义（上次活动？）；卡片底部孤零零的 “1”（疑为预览/计数）无标签。
- 过滤胶囊 `Working 0 / Offline 0 / Online 2` 在 2 个 agent 时是纯开销，`All 2` 与 `Online 2` 重复；零计数胶囊仍占触控位。
- 右上图标 `layers`（Group agents）没有文字，不可预测；大标题 + 状态行 + 胶囊行占首屏近 1/3，内容 2 行就见底。
- 在线点（绿）与 Working 同为小圆点，working 靠极细文字区分；离线/最后已知态靠 banner，行内无差异。
- 底部 Tab 仅 2 项，其中一项（Settings）低频，却永久占 ~90pt。

设置
- 机器名重复两次（标题 + mono 副标题完全相同）；`Remove` 红字紧贴行内、无二次确认路径提示，易误触且不可发现“重命名”。
- 区块标题全大写 + 字距（MACHINES / RELAY…），与正文层级差异小；“Hide tool calls in chat” 无说明；文字大小无预览。
- Relay 行：状态只有一个小绿点 + Reachable，主机名 mono 无截断策略；底部内容被 Tab 栏压住（About 被切）。

Relay
- “Messages pass through it.” 没说明谁能读；这是信任边界的关键点，当前文案容易被理解成“安全通道”。
- 输入框无标签/粘贴/清除，主按钮永远是蓝色满幅，看不出是否有改动；“Use community relay” 是低对比文字链接，没有警示这会改变隐私前提；检查结果（成功/失败/检查中）截图里没有任何位置。
- 切换 relay 会让已配对 Mac 变离线（必须同 relay），当前没有提前告知。

## 信息层级与关键交互

### 首页 Agents
- 顶栏：右上齿轮（44pt，`aria-label=Settings`）；大标题 Agents，下滚后折叠成顶栏标题 + 底线。
- 状态行：`● Relay connected` 一行；relay 失联时变 `◐ Relay offline · retrying` 并出现 banner（原因 + 最后已知时间 + 44pt Retry）。Retry 后 1.2s 恢复，toast “Relay connected”。
- 机器卡（surface，r=20）：头部 = 状态点 + 机器名 + `Online · 2 agents · 1 working`。机器离线时头部变 `Offline · seen 12m ago`，竖线变虚线，行内仅留 “Offline”，不再重复时间。
- Agent 行（≥76pt，整行可点）：
  1. 名称（17/600，单行省略）+ 右侧相对时间（ink2，tabular）
  2. 路径尾部两段 `…/acme/api-gateway`（mono 12，完整路径在 Session info 里可复制）
  3. 状态 pill（Working=琥珀软底 + 三条跳动竖线；Idle=绿字；Offline；Last known）+ 模型名（弹性省略）+ `Think low`（固定宽，不被挤掉）
  4. 最近一句预览，1 行省略
- 排序：working 优先，其次最近活动。分组固定按机器（去掉 Group 切换）。过滤：agent ≤ 5 个不显示过滤；≥ 6 个才出现 `All / Working / Offline` 分段（零计数不渲染）。原型未画该分段（没有 ≥6 的数据），属实施规则。
- 空态：`No Mac paired yet` + 主按钮 Pair a machine；已配对但无 agent：`Open Pi on this Mac and run /remote-pi`。

### 聊天
- 顶栏：返回（44pt）+ 名称 + `● Working · 机器名`（aria-live）+ info。
- 上下文条（44pt）：**模型 chip 可点**（模型名省略 + `Think low` 固定 + ▾）→ 底部 sheet：模型列表（最多 2 行，副标题 provider · ctx · reasoning）+ Thinking 分段（Off/Min/Low/Med/High/X-High）。右侧 working 时显示计时 `0:44` + 竖线动画。取代“藏在 Quick actions 里再进二级页”的路径。
- 消息：用户=蓝灰气泡（右，r20/6），agent=无气泡正文 16/24，代码块 surface2 + mono，工具调用=可折叠一行（文件名 mono 省略 + 耗时 + chevron；`Hide tool calls` 开启后整行不渲染）。
- 流式：文字逐词追加；用户上滑后不抢滚动，出现 `↓ Latest` 药丸（44pt）。
- 输入：`＋图` · 文本框 · 圆形主按钮。状态机：空闲+空=Mic；空闲+有字=Send；working+空=**Stop**（ink 实心方块）；working+有字=Steer（发送）+ 左侧小 Stop 并存，保证任何时刻都能停。Stop 立即结束并保留已收文本，列表追加 `You stopped this response · 0:44` 标记，状态回 Idle（不可撤销，故用 heavy 触感）。
- 离线 / relay 失联：整页只读，一条 banner：`Studio MacBook Pro is offline — read only` + 原因 + `Reconnect`；输入框禁用，占位 “Mac is offline — read only”。Reconnect → 按钮内 spinner（“Connecting”）→ 失败则文案变 “Still offline. Wake the Mac or open Pi, then try again.” 可再试；成功回到 Idle + toast。
- Session info sheet：名称/路径（mono，任意位置断行）/机器/模型/Thinking/配对日期，`Copy path`。

### 设置
- 返回 `‹ Agents`；大标题；分组标题改为句首大写 13/600（去掉全大写字距）。
- Machines：机器行（状态点 + 名称 + `Online · paired 23 Oct`，只显示一次）→ 点进 sheet：状态/配对时间/Agents，`Rename`、`Remove this Mac`。Remove 要二次确认 sheet：“This phone will stop showing its agents… Nothing is deleted on the Mac.” + 红色 Remove Mac / Cancel（heavy 触感）。`Pair a machine` 在列表内（蓝色、+）。
- Relay：一行（状态点 + mono 主机名 + 状态 + 社区标记）→ Relay 页；脚注 “Every paired Mac must use this relay. Messages aren’t end-to-end encrypted.”
- Appearance：主题分段（即时生效）；Text size 分段（即时缩放，下方有样例行）；`Hide tool calls in chat` 开关 + 一行说明。
- About：Version / Check for updates / Licenses。底部留 56pt 安全区不被遮挡。

### Relay（检查并保存）
- 文案：“The relay passes messages between this phone and your Mac.” + 提示框 `Who can read them`：“The connection uses TLS, but messages are not end-to-end encrypted. The relay’s operator can read them, so choose one you run or trust.”
- 两个 radio 行：My own relay（自建/Tailscale）/ Community relay（共享，他人运营，更省事但更不私密）。选社区时脚注变为强提醒。
- URL 输入（≥16px 防 iOS 缩放）+ 粘贴按钮；标签在输入框上方，不用 placeholder 当标签。
- 主按钮状态：无改动=次按钮 `Check again`；有改动=主按钮 `Check & save`；检查中=spinner + `Checking…`（禁用）；失败=`Try again` + 文本链接 `Keep current relay`（回滚草稿）。
- 提交前：地址格式无效 → 行内错误（不发请求）；已有机器且 relay 变化 → 确认 sheet：“Your Mac must use X too, or it will show as offline here until you change it there.” → `Check & switch`。
- 结果：成功 → success 触感，0.7s 后自动返回设置，toast `Relay saved · reachable 76 ms`；失败 → error 触感，输入框红边 + 原因 + 修复 + “Your current relay is unchanged.”。原型里 URL 含 “down” 会失败。

### 配对 / 首次进入
- 首次进入（Welcome）：App 图标 + “Check in on your Pi agents” + 一句价值 + 诚实提示（“Messages travel through a relay and are not end-to-end encrypted. Relay: Community [Change]”）+ 主按钮 `Pair your first Mac` + 文字按钮 `I’ve paired before`。把原来的 Welcome → Relay → Pair 三步压为 Welcome → Pair，relay 默认社区且可在提示行改。
- 扫码页：两步说明卡（命令 `/remote-pi pair` 带 44pt 复制按钮）→ 方形取景框（四角 + 扫描线；原型点击取景框模拟扫描）→ `Paste code instead`（48pt 次按钮）→ `Relay <host> Change`（44pt 高）。首次进入才显示 `Scan later`。相机权限被拒/不可用：取景框内显示 “Camera access is off” + Open Settings + Paste code instead（沿用现有源码行为，未在原型画出）。
- 粘贴 sheet：多行 mono 输入；空 → “Paste a code first.”；非 `perch://pair` → “That’s not a Perch code / Expected the code shown by /remote-pi pair.”（立即，不进入连接态）。
- 连接中：3 阶段列表（Reaching relay host → Waiting for your Mac to answer → Confirming pairing，✓ / spinner / ·）+ 已用秒数 + Cancel。
- 成功：绿色大对勾（弹入）+ `Paired with Studio MacBook Pro` + `2 agents are running there.` + `Open agents`。
- 错误（原因 + 修复 + 下一步）：Can’t reach the relay（Try again / Change relay）、Your Mac didn’t answer（Try again / Change relay）、Code expired（Scan again / Paste code）、That’s not a Perch code（Scan again / Paste code）。其余 token_consumed / token_unknown 沿用源码 copy。恢复路径：主按钮回到扫码；Change relay 进入 Relay 页，返回后仍在配对页。

## Tokens

沿用现有 `AppColors / AppTypography` 全部值（见 front matter），不引入新字体或新色相。

Proposed additions（仅 1 个 token + 3 条规则）
- `workingText` light `#9A5500`：琥珀文字用。原 `working #A65D00` 在 `workingSoft` 上仅 4.28:1（不过 AA）；新值 4.88:1（软底）/ 5.11:1（bg）。圆点、竖线等非文字仍用 `working`。dark 不变。
- 规则：`ink3` 只用于图标/分割/装饰（对 bg 仅 3.18:1，不够做文字）；时间、元数据一律 `ink2`。
- 规则：状态形状固定 —— 在线/Idle=实心绿点；Working=琥珀实心 + 向外扩散环；Offline=空心灰环；Last known=半实心灰（左半）；Checking=蓝空心环。
- 规则：分组标题改句首大写 13/600 `ink2`，取消 letterSpacing 0.6 的全大写样式。

对比度实测（WCAG，light / dark）
| 组合 | light | dark |
|---|---|---|
| ink / bg | 15.27 | 15.82 |
| ink2 / bg | 5.55 | 7.26 |
| ink2 / surface | 6.22 | 6.52 |
| accent / bg（文字链接） | 5.38 | 8.52 |
| onAccent / accent（主按钮） | 6.02 | 8.52 |
| workingText / workingSoft | 4.88 | 7.31 |
| online / surface（Idle 字） | 5.04 | 8.30 |
| error / bg | 5.00 | 6.82 |
| error / errorSoft | 4.58 | 5.57 |
| ink / userBubble | 14.04 | 10.77 |
| ink3 / bg（仅非文字，≥3:1） | 3.18 | — |

间距：页边距 20、卡内 16、行内元素间 8/12、卡间 16、分组标题上 24 下 8。圆角：卡 20 / 控件 14 / sheet 28 / 气泡 20+6 / pill 999。

## 动态、触感、可访问性

动态
- 页面 push/pop：320ms 横向滑入 / 滑出（`cubic-bezier(.2,.8,.2,1)`）；sheet 自下 320ms；toast 自上 220ms；Working 竖线 0.9s、状态扩散环 1.6s、扫描线 2.2s、光标 1s。
- **Reduce Motion（OS 或原型面板开关）**：所有 transition/animation 归零；push/pop 变瞬时；扩散环变静态半透明环；竖线变固定高度；扫描线停在中间；spinner 改点状环；光标不闪；流式文字改为每 0.7s 追加一小段而不是逐词；按压反馈由 scale(0.975) 改为仅 opacity .55（与现有“reduce motion 兼容按压反馈”一致）。
- 动效只表达状态变化（working、连接中、结果），不做装饰性淡入滑动。

触感（沿用现有轻触 / 选择 haptic，不新增类型）
- selection：分段/radio/开关/过滤/打开 agent/展开工具行/选模型。
- light：发送、复制、检查开始、Reconnect 开始、流式自然结束。
- success：配对成功、relay 检查成功、Reconnect 成功、Retry 恢复。
- error：配对失败、relay 失败、Reconnect 失败、无效代码。
- heavy：Stop、确认 Remove Mac。（若现有 `InteractionFeedback` 没有 heavy，用 `result()` / 现有最强档代替，不新增档位。）
- 原型右栏 `LAST HAPTIC` 显示触发的类别，便于评审。

可访问性
- 所有可点元素 ≥44×44pt（自动化遍历 6 个主屏的 button/radio/input/textarea，无 <44）；主按钮 52、次按钮 48。
- 状态 pill 与行 `aria-label` 带完整文字（名称、状态、模型、Thinking）；顶栏状态与 relay 结果区为 `role=status aria-live=polite`；错误标题获得焦点。
- 分段为 radiogroup，开关为 switch，sheet 为 `role=dialog aria-modal`，Esc 关闭并还原焦点；焦点环 2px accent。
- Text size（Small .92 / Default 1 / Large 1.12 / XL 1.25）作用于所有字号 token；XL 下行高自然增长，名称/路径/模型均单行省略，不横向溢出；Dynamic Type 同理使用 `MediaQuery.textScaler`，布局用 minHeight 而非固定高。
- 长文本：agent 名与路径单行省略（完整值在 Session info，路径任意位置换行并可复制）；模型名在行内/chip 内弹性省略、Thinking 固定不被挤；模型选择列表最多 2 行；中文 + 英文混排模型名已用 `标准 · Opus 4.1 long-context preview 20260415` 测过。
- 颜色之外的状态冗余：形状、文字、虚实线。

## Flutter 实施映射（建议顺序 = 风险从低到高）

| 设计元素 | 现有符号 | 改动 |
|---|---|---|
| 色板 / 字号 | `ui/core/themes/app_colors.dart` `app_typography.dart` | 仅新增 `workingText` 并用于 `StatusPill(working)` 与计时文字 |
| 状态点 5 种形状 | `core/widgets/status_dot.dart`（`AgentStatus`: working/online/offline/stale/checking） | 改绘制：stale 半实心、offline 空心环、working 扩散环（Reduce Motion 取 `MediaQuery.disableAnimations`） |
| 状态 pill | `status_pill.dart` | 新增 idle / stale 变体；working 前加竖线 |
| 首页卡 + 行 | `home/home_page.dart`、`home/widgets/agent_row.dart`、`session_tile.dart` | 分组固定按机器；行改为 4 行结构；删 hostname 胶囊、`Group agents`、`HomeFilterTabs`（≥6 才渲染）；竖线用 `CustomPaint`/`Stack` |
| 顶栏齿轮 + 去 Tab | `routing/app_router.dart`、`ui/navigation/main_tabs.dart` | `/home` 改为栈根，`/settings` 用 `context.push`；MainTabs 可保留给 iPad 自适应分栏（`routing/adaptive.dart`）不动 |
| Relay banner | `core/widgets/app_banner.dart`、`home_page.dart:131` | 补 44pt 按钮与副文案 |
| 聊天上下文条 | `chat_page.dart:168-250` 顶栏；`quick_actions/widgets/model_picker_sheet.dart`、`quick_actions_sheet.dart` | 模型 chip 直接 `showModalBottomSheet` 打开合并后的“Model + Thinking”sheet（复用 ViewModel）；Quick actions 里的 Model 行保留或删除均可 |
| 输入框状态机 | `chat/widgets/input_bar.dart` 的 `ComposerMode {mic,send,stop,steer}` | 逻辑不变；只调视觉与离线占位文案；Stop 标记消息 `You stopped this response` 为 `message_list` 的新 item 类型 |
| 离线 banner | `chat/widgets/chat_status_banner.dart` | 增加 Reconnect 进行中态（按钮内 spinner）与失败副文案 |
| Session info | `chat_page.dart:271-305` | 路径行换为 `SelectableText` mono + Copy path 按钮 |
| 设置 | `settings/settings_page.dart`、`widgets/peer_list_item.dart` | 机器行点击进 sheet（Rename/Remove）；Remove 加确认（已有 `revoke_confirm_dialog.dart` 可改文案）；删除 `Control` 区块（本版已关闭）；分组标题改句首大写 |
| Relay 页 | `settings/relay_page.dart`、`onboarding/widgets/relay_step.dart` | 增 radio（own/community）、检查结果行、确认 sheet；文案按上文，**不得出现 E2E 肯定表述** |
| Welcome / 配对 | `onboarding/onboarding_page.dart`、`welcome_step.dart`、`pairing/pairing_page.dart`、`states/pairing_error_copy.dart` | relay_step 并入 welcome 提示行；错误文案沿用，已符合“原因+修复” |
| Icon | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | 用 `icon/perch-icon-1024.png` 生成各尺寸（不预切圆角，Apple 自动遮罩） |

## Do / Don’t
- Do 一屏一个主操作；错误文案写“原因 + 下一步”；危险操作二次确认且说明后果；离线始终只读并给出恢复按钮。
- Do 把可变长文本放在弹性省略区，把固定语义（Think low、状态）放在不被挤压区。
- Don’t 写 “end-to-end / E2E / 加密通道”；Don’t 用颜色单独表达状态；Don’t 在首页重复 hostname；Don’t 恢复被关闭的功能入口；Don’t 用全大写字距的区块标题。

## Decisions（可逆项，已定）
- 去掉底部 Tab、齿轮入口 —— 2 个目的地且 Settings 低频，换回首屏高度与聊天全屏。
- 首页只按机器分组 —— 原截图里项目名 = agent 名，按项目分组只产生重复。
- 模型 chip 提到聊天上下文条 —— 模型/思考是聊天的一等信息，原来要 3 步到达。
- Relay 用 radio 行代替“Use community relay”链接 —— 当前选择可见，隐私差异就在选项旁。
- Reconnect 首次失败再成功（仅 Mac 离线场景的原型数据）—— 用来演示恢复路径，不代表真实重试策略。
- 配对错误触发一次后自动复位为成功 —— 便于评审走完恢复路径。
- 分段/过滤零计数不渲染 —— 避免无用触控位。

## Open questions（沿用推荐默认，除非你否决）
1. 去 Tab 属于信息架构改动：默认采用；若想保留 Tab，则 Settings 回到 Tab，齿轮删除，其余不变。
2. Relay 默认值：社区 relay 仍作默认（零配置），但首次引导已写明“非端到端、运营方可读”。若你想默认自建，Welcome 提示行需改成必选。
3. “Stop” 是否需要撤销：默认不需要（保留已收文本 + 标记）。

## App icon

文件（均在 `icon/`）：`perch-icon.svg`（主，1024 坐标、满铺方形、不含圆角）、`perch-icon-1024.png`（rsvg-convert 导出）、`perch-icon-alt-dot-on-rail.svg` + `-1024.png`（备选）、`icon-size-preview.svg/png`（180/120/60/32/16pt，已套 iOS 圆角蒙版预览）。
- 概念：一只由单个圆构成的“鸟”落在一根圆端栖木上 —— 同时也是产品最核心的语义“状态点停在一条线上”。琥珀色喙 = 产品里 *Working* 的颜色；眼睛为负空间，16pt 时自然消失，剩下“白圆 + 横条 + 一点琥珀”仍可辨。
- 颜色：背景 `#1D5FC4`（accent）、鸟与栖木 `#F4F2EC`（bg）、喙 `#F2A93B`。纸白对蓝 5.38:1。琥珀喙对蓝仅 3.02:1，属装饰色，不承载必须信息。
- 构图：安全区 112–912；鸟圆心 (436,490) r=262，栖木 x124–900、y728–824、圆端；圆沉入栖木 24px 以“坐稳”；整体重心略偏左，喙指向右侧，避免对称呆板。
- 与旧图标（黑底白 π + 蓝点）区别：旧版依赖 “Pi” 字形，不表达 Perch 的“停靠 / 状态”；新版不含机器人/AI 星芒元素。
- 备选（dot on rail）：深色底，绿色“靶心”状态点（外环 + 暗内环 + 点）落在纸白栏上，更抽象、更像状态指示，但像相机/录制指示，品牌温度较弱，故非主推。
- 实施：把 `perch-icon-1024.png` 放入 AppIcon 1024 槽，其余尺寸由 Xcode/脚本缩放；不要预切圆角、不要加透明通道。Dark/Tinted 图标变体（iOS 18+）未做，可由同一 SVG 去背景后派生。

## 验证记录与局限
- 在 Playwright Chromium headless shell 中实际跑通：首页→聊天（流式→Stop→Idle→再发送→Steer）→返回；聊天模型 sheet / Session info；设置→Relay（失败→回滚→成功→自动返回，设置行更新）；配对（过期错误→Scan again→连接中→成功→Open agents）；首次 Welcome、无机器空态、relay 失联 stale、Mac 离线、Reconnect 失败再成功、暗色、XL 字号、粘贴无效码；0 个 pageerror/console error；`node --check` 通过；唯一资源引用 `icon/perch-icon.svg`（favicon，已存在）。
- 自动遍历 6 个主屏全部可点元素尺寸 ≥44pt；OS `prefers-reduced-motion` 下 `data-rm=true` 生效，且流式仍可用。
- 430 宽窗口下手机壳自动铺满；≥861 宽时右侧为演示控制面板。
- 局限：未在真机 iOS Safari / Flutter 渲染；haptic 在浏览器里只更新面板读数；相机权限拒绝态、Rename、Licenses、Attach、语音按住说话仅给出 toast 占位；无 ≥6 agent 的过滤分段与 iPad 分栏稿；未做 components.html 与应用内组件陈列页；JetBrains Mono 在未安装的浏览器上回退到系统等宽。
