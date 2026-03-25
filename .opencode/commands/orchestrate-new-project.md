---
description: Assigns agent the orchestrate-new-project assignment
model: openai/gpt-5
---

## Inputs

- $new-repo-name: string (pass as first argument via $1)
- $app-creation-docs: list(files) (pass as second argument via $2)

## Prompt

You have been assigned the `orchestrate-new-project` assignment with inputs($new-repo-name, $app-creation-docs)

<!--
The repo-name will be "support-assistant-copilot"

The attached files will be:
- https://github.com/nam20485/support-assistant2/blob/development/docs/Architecting%20AI%20for%20Open-Source%20Windows%20Applications.md
- https://github.com/nam20485/support-assistant2/blob/development/docs/ImplementationPlan.txt
- https://github.com/nam20485/support-assistant2/blob/development/docs/ImplementationTips.txt
- https://github.com/nam20485/support-assistant2/blob/development/docs/index.html
- https://github.com/nam20485/support-assistant2/blob/development/docs/ai-new-app-template.md
-->

<!-- Make use of your /mcp.gemini-cli tools to handle large contexts. -->

- Your custom instructions are located in the files inside of the [nam20485/agent-instructions](https://github.com/nam20485/agent-instructions) repository
- Look at the files in the `main` branch
- Start with your core instructions (linked below)
- Then follow the links to the other instruction files in that repo as required or needed.
- You will need to follow the links and read the files to understand your instructions
- Some files are **REQUIRED** and some are **OPTIONAL**
- Files marked **REQUIRED** are ALWAYS active and so must be followed and read
- Otherwise files are optionally active based on user needs and your assigned roles and workflow assignments

## Core Instructions (**REQUIRED**)
[ai-core-instructions.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-core-instructions.md)

## Creating Application Plan Specific Instructions (**REQUIRED**)
[orchestrate-new-project.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-workflow-assignments/orchestrate-new-project.md)
[ai-workflow-assignments.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-workflow-assignments.md)

### Sub-Assignments
These will help with the assignments included in your main assignment:
[create-app-plan.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-workflow-assignments/create-app-plan.md)
[create-application.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-workflow-assignments/create-application.md)
[create-project-structure.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-workflow-assignments/create-project-structure.md)
[initialize-new-repository.md](https://github.com/nam20485/agent-instructions/blob/main/ai_instruction_modules/ai-workflow-assignments/initialize-new-repository.md)

After reading the instructions for your workflow assignment begin orchestrating the project.

<!--
copilot-source:
  file: orchestrate-new-project.prompt.md
  mode: agent
  model: GPT-5 (Preview)
  tools:
    - codebase
    - usages
    - vscodeAPI
    - think
    - problems
    - changes
    - testFailure
    - openSimpleBrowser
    - fetch
    - findTestFiles
    - searchResults
    - githubRepo
    - extensions
    - runTests
    - editFiles
    - runNotebooks
    - search
    - new
    - runCommands
    - runTasks
    - sequential-thinking
    - memory
    - github
    - filesystem
    - gemini-cli
    - context7
    - microsoft-docs
    - deepwiki
    - playwright
    - copilotCodingAgent
    - activePullRequest
    - openPullRequest
-->
