自从上一次更新以来，小彭老师最近发现Claude Code易用性提升啦！

感觉明显把OpenCode UI上的优点都抄过来了x

支持了虚拟终端，全屏显示，不用再依赖终端的回滚历史，这同时也彻底解决了长上下文时，屏幕鬼畜闪烁的bug：/tui fullscreen或设置export CLAUDE_CODE_NO_FLICKER=1即可开启！

可以用鼠标滚动，也可以按pageup pagedown滚动，还可以用鼠标点击移动光标，鼠标拖拽复制文字。

（这些都是OpenCode之前的功能哇🤔

现在支持/focus模式，一轮对话内的执行细节不再显示，点击鼠标展开观察工具调用，或者ctrl+o显示完整内容。之前我用的时候，调用了很多工具，编辑了很多文件，就会导致定位到我自己的上一句提问的位置非常困难，一度想不起来我刚才要干什么，以及claude回复针对的我的问题是什么。

现在支持了/recap，自动为当前会话生成一个概述，完成了什么，非常适合习惯多开Claude Code的用户快速回忆之前工作进度。也可以/rename生成一个标题，防止忘记每个会话在做什么，还有/color也可以帮助提升辨识度。之前我就tmux开了几十个claude窗口，结果切来切去大脑空白，当初开这个pane是啥来着，反复翻阅上下文回忆。

还有新增了Monitor工具，/loop定时重复执行，/schedule设置定时任务，ctrl+r搜索历史输入，/btw添加一条不占用上下文的一次性小提问。

还介绍了vim用户狂喜的功能：按下ctrl+g可以切换到在vim中畅快编辑提示词（而不是狭小的文本框），ctrl+o展开详细模式后按v在vim中打开完整对话记录，畅快搜索。

推荐配合Kitty和Ghostty终端使用：1. 鼠标拖拽需要这两个终端的OSC 52剪切板支持，2. claude陷入等待，或问问题等你回复时：会自动发出桌面通知，让你去办理，防止claude陷入干等，你还不知道。3. 内置的分屏功能也很适合需要多开claude code的用户，虽然我更喜欢用tmux分屏。

以及老早就有的暂存当前提示词给后面让道(ctrl+s)，感叹号就地执行bash命令（claude可以看到输出的）。

以上介绍的功能都是Claude Code的功能，不需要Claude订阅，用其他替代厂商都可以用出来。Claude官方订阅才能用的功能/chrome和/remote-control就不介绍了，以及更新了Opus 4.7模型（现在用户都褒贬不一的，我的感觉说话更slop味了，但是更遵守用户指令，更少调用工具，默认xhigh导致思考比4.6的默认medium更久等）。

小彭老师自用Claude Code配置分享：https://github.com/archibate/dotfiles-claude

其他自用配置分享（包括Kitty终端配置）：https://github.com/archibate/dotfiles



Claude Code命令行安装教程（Claude官方的文档）：https://code.claude.com/docs/en/overview

Linux安装命令：curl -fsSL https://claude.ai/install.sh | bash

Windows安装命令：irm https://claude.ai/install.ps1 | iex

顺便一提Claude Code也有桌面版和IDE插件（VSCode和JetBrain的都有）



点击以下两个链接的同学请注意：小彭老师与质谱从未合作！之前也没有合作过，很抱歉导致很多同学误解！它这个邀请码是每个人都能生成的，小彭老师生成给你用这个只是为了能蹭到它的优惠。警告：现在GLM在对话较长时很大概率输出乱码！输出恐怖谷风格的胡话，像是tokenizer坏了，担心输出bash命令破坏我系统就没再用了。GLM降智成这样了，搞不懂它们黄牛在抢什么，全靠刷跑分刷出来的热度。但还是放了GLM邀请码，如果有人铁定了要买GLM的话可以通过这个蹭到优惠，不代表小彭老师还推荐GLM。

安装教程（智谱的“强兼”方案）：https://docs.bigmodel.cn/cn/coding-plan/tool/claude

小彭老师生成的智谱邀请码：https://www.bigmodel.cn/glm-coding?ic=DS9Z8XI6CS

如果富有同学们想用Claude官方模型，可以去淘宝上买成品订阅号，或者openrouter上买api按量付费。感觉目前a手在整活，为了“网络安全计划”把新模型阉割了不少，用不了的同学可以先用codex的模型替一替（群友说codex开个支持外币的信用卡就能买到？不会封号），而不是诉诸所谓的“中转站”
