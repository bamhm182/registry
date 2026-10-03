---
display_name: Moshi
description: Adds a coder_app to easily connect via Moshi mobile phone application.
icon: ../../../../.icons/moshi.svg
verified: false
tags: [helper]
---

# Moshi

The [Moshi](https://getmoshi.app) website describes it as:
"Moshi 🐱 is the baby monitor for your AI agents — a terminal built for phones, not shrunken from desktops.

Check on your agent from the couch 🛋️, the beach 🏖️, the coffee shop ☕, the bed 🛏️ — anywhere."

Moshi is an agent-first terminal client built for easily connecting to workspaces from mobile devices. It provides a very nice interface for either typing or voice to text (powered locally by Whisper or in the cloud). It provides a very smooth mobile experience whether you're typing commands into a shell or speaking with an agent who is using the workspace on your behalf.

Moshi integrates very will with Herdr to juggle multiple agents at once, and a wide variety of agents, such as Pi, Claude, Codex, and many more.

```tf
module "moshi" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/bamhm182/moshi/coder"
  version = "1.0.0"
}
```