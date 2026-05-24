# Information flow

Your expression has type `DC a` — an `LIO DCLabel` action.

## Labels

A `DCLabel` is written `secrecy %% integrity`:

- **secrecy** — which principals may read the value.
- **integrity** — which principals endorsed the value.

Named components you can use with `%%`:

- `public` / `secret` — for the secrecy component.
- `trusted` / `untrusted` — for the integrity component.

A `DCLabeled a` is an `a` tagged with a `DCLabel`. Reads return
`DCLabeled` values, so the taint is visible in the type.

## Current label and `unlabel`

Your computation has a floating *current label*; read it with
`getLabel :: DC DCLabel`. It is raised by `unlabel`:

    unlabel :: DCLabeled a -> DC a

`unlabel` extracts the underlying value and raises the current
label by that value's label.

## State-changing tools

Writes that take a `DCLabeled` argument check three things: the
integrity of that argument, the label of the data, and the current
label. Maximize the integrity of the labeled argument — labeling
with the current label (rather than constructing a fresh one)
gives the most integrity available at that point.

Writes that take plain (unlabeled) arguments unconditionally
require current to be trusted.

## `toLabeled`

    toLabeled :: DCLabel -> DC a -> DC (Labeled DCLabel a)

`toLabeled lbl action` quarantines `action` inside a label `lbl`
you supply. `lbl` must be at or above the current label. The inner
action's taint stays inside the returned `DCLabeled` value.

    body <- toLabeled (secret %% untrusted) $ do
              page <- getWebpage url
              raw  <- unlabel page
              pure (subagent "Summarize this." raw :: String)

Generally wrap `subagent` calls in `toLabeled` — a subagent may
read or unlabel external data and the wrap keeps that taint
contained.

## Separate via `toLabeled`

Separate independent computations into their own `toLabeled` blocks
to keep taint from spreading between them. Each block should be
self-contained — do only the reads and unlabels for one logical
unit so its wrap label can stay tight.
