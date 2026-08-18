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

## Why SpringNote-Agenda

Writing down one thing is easy — but organizing many scattered notes together takes time, and it's why many people struggle to keep a consistent journaling habit.

SpringNote-Agenda removes the organizing step: record your thoughts and daily moments anytime, and AI organizes them into daily, weekly, and monthly reports — turning scattered fragments into a complete whole automatically.

With "Memories", you can also search and chat with your past notes, bringing back anything you once wrote down.

SpringNote-Agenda aims to make recording your life easier to stick with, with the help of AI.


## Core Features

- **Home Dashboard**: Activity heatmap, quick input box, and today's summary card.

  ![SpringNote-Agenda Home](./snapshots/index.png)

- **AI-Powered Generation**: Quickly jot down ideas on the home page, and AI automatically organizes them into structured content.

- **Note Editor**: Supports daily, weekly, and monthly notes, with Markdown editing, preview, code block highlighting, and AI completion suggestions.

  ![SpringNote-Agenda Note](./snapshots/note.png)

- **Project Calendar**: Detects deadlines written in notes and displays them in a calendar with overdue, due-today, and upcoming reminders. Supported examples: `Due: 2026-08-30`, `Deadline: 2026/08/30`.

- **Memories Chat**: Retrieve and organize your memories through conversation, with visible thinking process, tool call display, and Markdown rendering.

  ![SpringNote-Agenda Memories](./snapshots/memories.png)

- **Automatic Report Generation**: On startup, fills in missing weekly/monthly reports based on existing daily or weekly notes.

- **Statistics Panel**: View records, activity, model calls, and data overviews across time ranges.

  ![SpringNote-Agenda Statistics](./snapshots/setting.png)


- **Polished Desktop Experience**: Custom Windows title bar, system tray, launch on boot, global shortcuts, and system font switching.

## Quick Start

### Download & Install

#### Download from GitHub

Go to the [Releases page](https://github.com/Adorable-Qin/SpringNote-Agenda/releases/latest) to download SpringNote-Agenda.

### Step 1: Confirm the Data Directory

Before first use, confirm where your data will be stored. Daily, weekly, and monthly notes, images, and related configs are all saved around this directory.

![Data Directory](./snapshots/datadir.png)


### Step 2: Configure AI

We use **DeepSeek** as an example:

#### ① Add a provider — set the BaseURL to https://api.deepseek.com/beta

>
> The `beta` path is used here because of DeepSeek's [FIM API requirements](https://api-docs.deepseek.com/guides/fim_completion).
>
> For other OpenAI-compatible APIs, fill in the BaseURL according to your provider's documentation.
>

![Step 1](./snapshots/configone.png)

#### ② Manually add the model `deepseek-v4-flash`

>
> DeepSeek's `beta` endpoint does not support listing models, so the model must be added manually.
>

![Step 2](./snapshots/configtwo.png)

#### ③ Edit the model

>
> Manually check the completion capability option.
>

![Step 3](./snapshots/configthree.png)

#### ④ Select the default model

>
> If a model doesn't support completion, it won't appear in the completion model list.
>

![Step 4](./snapshots/configfour.png)

### Step 3: Create Your First Note

![Home](./snapshots/index.png)


### Step 4: View and Edit in the Notebook

![Notebook](./snapshots/note.png)

Notebook search only searches within the currently selected note type (daily, weekly, or monthly). Enter at least two characters to search; click a result to open its full content.

### Step 5: Use Memories

![Memories](./snapshots/memories.png)

In "Memories", you can directly ask questions about your saved work records.

### Step 6: Manage Deadlines in the Project Calendar

Write a deadline in any daily, weekly, or monthly note, for example:

```markdown
- Prepare the release notes — Due: 2026-08-30
- Submit the proposal — Deadline: 2026/09/05
```

Open **Project Calendar** from the sidebar to see overdue, due-today, and upcoming items. Completed Markdown tasks such as `- [x] ...` are ignored.

### Keep Exploring

After finishing the basics, you can continue configuring in Settings. For more usage instructions, see the [documentation](./docs).

## 🌍 Community

Whether you've run into an issue while using SpringNote-Agenda, or you have new ideas and suggestions, you're welcome to talk with us.

We read every piece of feedback carefully and keep improving SpringNote-Agenda to make it better.

> [!TIP]
> When reporting an issue, please also provide:
> - Your current version number
> - Steps to reproduce
> - Whether it can be reproduced consistently
> - Relevant screenshots or error messages
>
> This information helps us locate the problem quickly.


## License

SpringNote-Agenda and the modifications in this repository are distributed under **GNU Affero General Public License v3.0 only (AGPL-3.0-only)**. If you distribute a modified version or make it available for users to interact with over a network, provide the corresponding source code as required by the license. See [LICENSE](./LICENSE).

## ❤️ Special Thanks

Special thanks to all Contributors and community members for supporting SpringNote-Agenda ❤️

<a href="https://github.com/Adorable-Qin/SpringNote-Agenda/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Adorable-Qin/SpringNote-Agenda&max=300&columns=15" />
</a>

## ⭐ Star History

> [!TIP]
> If this project has helped your life or work, or if you're following its future development, please give it a Star — that's what keeps us maintaining this open-source project <3

<p align="center">
  <img src="https://count.getloli.com/@SpringNote-Agenda?name=SpringNote-Agenda&theme=miku&padding=7&offset=0&align=center&scale=0.3&pixelated=1&darkmode=auto" alt="visitor count" />
</p>

[![Star History Chart](https://api.star-history.com/chart?repos=Adorable-Qin/SpringNote-Agenda&type=date&legend=top-left)](https://www.star-history.com/?repos=Adorable-Qin%2FSpringNote-Agenda&type=date&legend=top-left)
