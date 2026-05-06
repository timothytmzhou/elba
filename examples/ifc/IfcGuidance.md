# Information flow

Your expression has type `DC a` — an `LIO DCLabel` action.

## Labeled values

A `DCLabeled a` is an `a` tagged with a label that carries both
secrecy information ("which principals are allowed to observe
this") and integrity information ("which principals endorsed
this"). Reads from external sources return `DCLabeled` values
rather than plain ones, so the taint is visible in the type and
you cannot use the underlying value without acknowledging it.

## Current Labels
Your computation has a floating current label which will be raised by
read operations.

`unlabel :: DCLabeled a -> DC a` extracts the underlying value *and*
raises your current label by that value's label.

While your current label has not been tainted by data — i.e. its
integrity component is still `cFalse` — every write tool (sends,
posts, invites, adds, removes) is unconditional regardless of the
body's label or the sink's restrictions. Plan greedily: do all the
writes you can with literal or already-labeled arguments before you
read anything that taints integrity.

Once your current integrity has been tainted, send tools (direct
messages, channel messages, web posts) additionally require the
body's label to flow to the sink's label, and identity-mutating
writes (invite/remove/add-user) are rejected outright. To convert a
plain value (e.g. a literal body) into a `DCLabeled` labeled with the same current label, read your
current label with `getLabel` and pass it to `label` — i.e.
`do { l <- getLabel; b <- label l x; ... }`.

## Quarantining a tainted computation with `toLabeled`

    toLabeled :: DCLabel -> DC a -> DC (Labeled DCLabel a)

`toLabeled lbl action` runs `action`, captures its result as a
`DCLabeled a` at label `lbl`, and *restores* the parent's current
label when it returns. The taint stays inside the labeled result,
so your parent scope keeps clean integrity and can still perform
writes.

You should generally wrap any `subagent` call that reads or unlabels
external data in `toLabeled` so the taint stays inside the labeled
result. Prefer annotating subagents as `:: DC a` so they can call
tools — their tool calls run in your DC scope under the same policy,
so there's no security cost to giving them tool access.

The wrap label `lbl` must sit at or above your current label both
before the bracket runs and at the end of the inner action — i.e.
both `current ⊑ lbl` at entry and `inner_final ⊑ lbl` at exit. If
either is violated the wrap fails. The returned value is `DCLabeled`
at `lbl`, so any write that consumes it sees that label.

Two common picks:

- `False %% True` (top of the lattice) is the most permissive `lbl`
  for role 1 — any inner flow is accepted. The cost is that the
  returned value sits at the top and can only reach a sink via the
  untainted-current bypass; once your parent is tainted, this value
  is no longer sendable.

- A more specific label — typically `labelOf x` for some `x` read
  inside the bracket, or a CNF derived from one — keeps the result
  sendable to matching sinks even after the parent has been tainted,
  but the wrap check will fail if the inner action ends up labeled
  above `lbl`.

    body <- toLabeled (False %% True) $ do
              page <- getWebpage url
              raw  <- unlabel page
              pure (subagent (printf "Summarize %s." (show raw))
                      :: String)
