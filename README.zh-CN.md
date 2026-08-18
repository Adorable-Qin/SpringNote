<!-- We've seen that note-taking tools usually just store text.
But SpringNote-Agenda treats notes as something that grows over time.
Instead of static records, we model a living system:
  .     *   .       .        o        .       *     .   .
    .   .      |     .    .        .     .     *   .     .
       --o--           SpringNote-Agenda           .      |   .
    *    |      .   capture → organize → reflect → grow
 .    .     .     .        .        .     .   --*--   .
      .        *      .        .     .        |     .  .
(ASCII art depicting scattered thoughts converging into SpringNote-Agenda) -->

<h1 align="center">
  <img src="./snapshots/logo.png" width="48" alt="SpringNote-Agenda Logo" style="vertical-align: -6px;">
  SpringNote-Agenda
</h1>

<div align="center">
<div>
<img src="https://img.shields.io/badge/Flutter-3.x-d7e8e4?style=flat-square&labelColor=263a36&logo=flutter">
<img src="https://img.shields.io/badge/Rust-2024-e8dfd8?style=flat-square&labelColor=263a36&logo=rust">
<img src="https://img.shields.io/badge/License-AGPL--3.0-f2e8e5?style=flat-square&labelColor=5b403a">
</div>
<p><a href="./README.md">English</a> | <a href="./README.zh-CN.md">简体中文</a></p>
</div>

## 为什么选择SpringNote-Agenda

记录一件事很简单，但把多条记录整理到一起很花时间，也让很多人难以坚持用文字记录下自己。

SpringNote-Agenda 想省掉整理这一步：你可以随时记录想法和日常，AI 会帮你把这些内容整理成日报、周报和月报，让零散的记录自动汇总成一份完整的内容。

通过「回忆书」，你还可以对过去的记录进行搜索和对话，随时找回曾经记下的信息。

SpringNote-Agenda 希望通过 AI 让记录这件事更容易长期坚持。


## 核心功能

- **首页工作台**：活跃热力图、快速输入框和今日摘要卡片。

  ![SpringNote-Agenda 首页](./snapshots/index.png)

- **AI 智能生成**：在首页快速输入想法，由 AI 自动整理为结构化内容。

- **便签编辑**：支持日报、周报、月报等记录类型，提供 Markdown 编辑、预览、代码块高亮和 AI 补全预测。

  ![SpringNote-Agenda 便签](./snapshots/note.png)

- **项目日历**：自动识别笔记中的截止日期，并在日历中显示逾期、今日到期和即将到期提醒。支持示例：`截止日期：2026-08-30`、`到期：2026/08/30`。

- **回忆书对话**：以对话方式检索和整理记忆内容，支持思考过程、工具调用展示与 Markdown 渲染。

  ![SpringNote-Agenda 回忆书](./snapshots/memories.png)

- **自动报告生成**：启动时可按日期补齐缺失的周报/月报，基于已有日报或周报生成总结。

- **统计面板**：查看记录、活跃度、模型调用和时间范围内的数据概览。

  ![SpringNote-Agenda 统计面板](./snapshots/setting.png)


- **桌面端极致体验**：支持自定义 Windows 标题栏、托盘、开机自启动、全局快捷键和系统字体切换。

## 快速开始

### 下载安装

#### 通过 GitHub 下载

请前往 [Release 页](https://github.com/Adorable-Qin/SpringNote-Agenda/releases/latest) 下载SpringNote-Agenda

### 第一步：确认数据位置

首次使用时先确认数据保存目录。日报、周报、月报、图片和相关配置都会围绕这个目录保存；

![数据目录](./snapshots/datadir.png)


### 第二步：配置 AI


以 **DeepSeek** 为例进行配置说明：

#### ① 添加供应商 BaseURL请填写 https://api.deepseek.com/beta


>
> 此处填写`beta`原因是Deepseek的[FIM接口要求](https://api-docs.deepseek.com/zh-cn/guides/fim_completion)
>
>其他的OpenAI兼容接口请依据实际情况填写
>

![第一步](./snapshots/configone.png)

#### ② 手动添加模型 deepseek-v4-flash

>
>因为Deepseek的`beta`接口不支持模型列表查询，所以需要手动添加模型
>

![第二步](./snapshots/configtwo.png)

#### ③ 编辑模型

>
>请手动勾选补全类型
>

![第三步](./snapshots/configthree.png)

#### ④ 选择默认模型

>
>如果你的模型不支持补全类型，则在编辑补全模型列表中不会出现该模型
>

![第四步](./snapshots/configfour.png)

### 第三步：完成第一次记录

![首页](./snapshots/index.png)


### 第四步：在笔记本中查看和编辑

![笔记本](./snapshots/note.png)

笔记本搜索只搜索当前选择的日报、周报或月报类型。搜索至少输入两个字符，点击结果后可以打开对应的完整正文。

### 第五步：使用回忆书

![回忆书](./snapshots/memories.png)

进入“回忆书”后，可以直接询问已经保存的工作记录。

### 第六步：使用项目日历管理截止日期

在任意日报、周报或月报中写入截止日期，例如：

```markdown
- 准备发布说明 —— 截止日期：2026-08-30
- 提交项目方案 —— 到期：2026/09/05
```

从侧边栏打开**项目日历**，即可查看逾期、今日到期和即将到期事项。已经勾选完成的 Markdown 任务（如 `- [x] ...`）不会生成提醒。

### 继续探索

完成基本记录后，可以在设置中继续配置。更多使用说明请查看 [文档](./docs)

## 🌍 社区

无论你是在使用过程中遇到问题，还是有新的想法与建议，都欢迎与我们交流。

我们会认真聆听每一条反馈，持续优化 SpringNote-Agenda，让它变得更好。

>[!TIP]
>反馈问题时，请同时提供：
>- 当前版本号
>- 操作步骤
>- 是否能够稳定复现
>- 相关截图或错误信息
>
>这些信息可以帮助快速定位问题。


## 许可证

SpringNote-Agenda 及本仓库中的修改均以 **GNU Affero General Public License v3.0 only（AGPL-3.0-only）** 发布。分发修改版本，或通过网络向用户提供交互服务时，应按许可证要求提供对应源代码。详见 [LICENSE](./LICENSE)。

## ❤️ Special Thanks

特别感谢所有 Contributors和社区成员对 SpringNote-Agenda 的支持 ❤️

<a href="https://github.com/Adorable-Qin/SpringNote-Agenda/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Adorable-Qin/SpringNote-Agenda&max=300&columns=15" />
</a>

## ⭐ Star History

> [!TIP]
> 如果本项目对您的生活 / 工作产生了帮助，或者您关注本项目的未来发展，请给项目 Star，这是我们维护这个开源项目的动力 <3

<p align="center">
  <img src="https://count.getloli.com/@SpringNote-Agenda?name=SpringNote-Agenda&theme=miku&padding=7&offset=0&align=center&scale=0.3&pixelated=1&darkmode=auto" alt="visitor count" />
</p>

[![Star History Chart](https://api.star-history.com/chart?repos=Adorable-Qin/SpringNote-Agenda&type=date&legend=top-left)](https://www.star-history.com/?repos=Adorable-Qin%2FSpringNote-Agenda&type=date&legend=top-left)
