## Subagent-returned task-id "context token"

Incorporate this into `AGENTS.md` in a secton about delegtaiotn and subagent communication.

```
2. When the agent is done, it will return a single message back to you. The result returned by the agent is not visible to the user. To show the user the result, you should send a text message back to the user with a concise summary of the result. The output includes a task_id you can reuse later to continue the same subagent session.
```

Repply:

```
Bro, discovered that yesterday as well... Instantly integrated for my CodeReviewer subagent usage:

------

# CodeReviewer workflow

When iterating with CodeReviewer (review -> fix -> review):

First call: note the task_id returned | IMPORTANT! In case of compaction, you MUST pass down this value in the compaction summary

Fix the reported issues

Follow-up calls: MUST pass the same task_id to resume the session

Repeat until no critical findings

This maintains CodeReviewer's context across iterations, avoiding redundant re-analysis.
```

Add insrtrcutions for using subagents retuend the task-id to maintian continutiy across subagent delgation calls.


## Use `delegate` word specifically when instrcuting agent to delegate to subagents

Also add this direction where its relevant in existing instructoins.

When delegating to a subagent
