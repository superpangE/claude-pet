---
description: Control the claude-pet window and theme. /pet show|hide|list|set [idle|working] <theme>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/pet-control.sh:*)
argument-hint: show | hide | list | set [idle|working] <theme>
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/pet-control.sh $ARGUMENTS`

If the command above printed a `PET_PICK` block, ask the user via `AskUserQuestion` to choose a theme — show the listed `available:` names with the current `idle` / `working` selections highlighted, and let them pick which state to change (idle, working, or both) and which theme. Then run `/pet set [idle|working] <theme>` accordingly.
