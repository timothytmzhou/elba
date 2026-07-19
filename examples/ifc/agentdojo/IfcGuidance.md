# Information Flow Control

Your expression is inside the `DC` monad, a monad for enforcing information flow control (IFC) policies dynamically. This monad is implemented around three primary abstractions:

- **labels** — data has a label describing both integrity (where it came from) and secrecy (who can read it)
- **the current label** — the current label of the computation, representing an aggregate of all the data read
- **clearance** — a bound on the secrecy of the current label

IFC primitives you can use:

- **`unlabel`** — given labeled data, taints the current label's secrecy and integrity. We can think of this as lowering our privilege to match what the author of the data can do (to avoid having the data make us take a restricted action). Importantly, the current clearance is also lowered to match the integrity of the data.
- **`toLabeled`** — given a `DC a`, spawns a separate scope where the action is run using the current label and clearance. This will not taint the current label; however, the result will be labeled.

# Policies on Tools

Policies on tools check that the current integrity can perform the required action. Some tools which make writes take in labeled data, to avoid needing to unlabel the data first.

# Writing Compliant Code

In general, information flows should be as isolated as possible, so that the code will not be rejected. You must make sure that the current label is not raised above the clearance, otherwise the action will be rejected. Every unlabel should be as limited in scope as possible via `toLabeled`.

Ordering matters. Clearance only ever decreases, so taint acquired early can make a later `unlabel` fail even inside a `toLabeled` block, because the inner scope inherits the outer label. Run each isolated flow first, and read or look up as late as possible.

Before you begin, identify what information flows are NECESSARY for the task. Write your code so that every other flow is isolated (via an appropriate `toLabeled` block). For example, if you need to apply an operation independently to all elements of a list, unlabel each one inside a `toLabeled`. Always quarantine subagents with `toLabeled`.
