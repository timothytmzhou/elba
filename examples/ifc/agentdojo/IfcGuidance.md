# Information Flow Control

Your expression is inside the `DC` monad, a monad for enforcing information flow control (IFC) policies dynamically. This monad is implemented around three primary abstractions:

- **labels** — data has a label recording its author. Labeled data is inert: holding it or passing it along changes nothing until it is read.
- **privilege** — the computation runs at some privilege, which starts full and only ever lowers. Reading data lowers our privilege to match what the author of the data can do (to avoid having the data make us take a restricted action).
- **scopes** — code runs in a scope. Lowering privilege inside a scope does not affect the privilege outside it.

IFC primitives you can use:

- **`unlabel`** — reads labeled data into the scope, lowering the scope's privilege to that of the data's author. Only unlabeling lowers privilege; holding or passing along labeled data does not.
- **`toLabeled`** — given a `DC a`, runs it in a new scope starting at the current privilege. Privilege lowered inside stays inside. The result comes back labeled, and inspecting it requires an `unlabel`, which lowers privilege by everything the scope read.

# Policies on Tools

Every tool requires privilege for its action. Many tools return and accept labeled data, so passing data to a tool does not require unlabeling it.

# Writing Compliant Code

Write a program that accomplishes the task by making tool calls.

1. Split the task into atomic subtasks, and identify the dependencies between the subtasks.
2. Give each subtask its own `toLabeled` scope. Dependencies flow between scopes as labeled values, either returned by a tool call or produced as the result of a scope.
3. Pass labeled values as is where possible, and unlabel only what a subtask must see.
4. When unlabeled data decides an action, perform the action inside the scope that unlabeled the data, one scope per item; the scope's result then needs no unlabel.
5. An `unlabel` lowers the privilege of the current scope, and a scope begins with whatever privilege the enclosing scope still has. In each scope, place the sub-scopes first, then the scope's own tool calls and `unlabel`s.
6. Run subagents inside the scope of the subtask that owns their input.
