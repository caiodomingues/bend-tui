# bend-tui

Terminal interfaces for [Bend](https://bend-lang.com) 2, on
[bend-tty](https://github.com/caiodomingues/bend-tty). A `View` is a tree of
widgets; `render` lays it out into a frame of cells; `Frame.diff` writes only
the rows that changed; `Tui.run` is the loop, in the shape of Base's `App.run`.

Two facts about every frame are theorems, not tests: it has exactly `h`
rows, and every row has exactly `w` cells, for every view, size and state
(`render_rows`, `render_cols`); and a frame diffed against itself writes
nothing (`diff_self`), so an idle screen costs no output.

```python
import Base
import ../../bend-tty/tty.bend as T
import ../tui.bend as U

# the turn count; each bar is a phase of it
def step.at(+n: Nat, k: T.Key) -> Maybe<&2, Nat>:
  match k:
    case T.Esc{}:
      None{}
    case other:
      Some{n}

def step(n: Nat, k: T.Key) -> Maybe<&2, Nat>:
  step.at(n, k)

# an update with no keys is a tick
def update(ks: List<&2, T.Key>, n: Nat) -> Maybe<&2, Nat>:
  U.Tui.fold(~Nat, ~step, ks, Some{1n+n})

def panel(title: String, +n: Nat, +period: Nat, +color: U32) -> U.View:
  U.Boxed{title, U.Above{
    U.Text{U.Style.plain(), Nat.show(Nat.mod(n, period)) ++ " / " ++ Nat.show(period)},
    U.Progress{Nat.mod(n, period), period, U.Style.fg(color)},
    1n}}

def view.at(+n: Nat) -> U.View:
  U.Below{
    U.Beside{panel("cpu", n, 40n, 42), U.Beside{panel("mem", n, 90n, 214), panel("disk", n, 200n, 203), 26n}, 26n},
    U.Boxed{"log", U.Lines{U.Style.fg(245), ["turn " ++ Nat.show(n), "Esc quits"]}},
    4n}

def view(n: Nat) -> U.View:
  view.at(n)

def main() -> IO(Unit):
  U.Tui.run(~Nat, ~U.Tui{view, update}, 0n, 100)
```

That is `demos/dashboard.bend`. `demos/todo.bend` is a list with an input:
type and Enter to add, Up/Down, Tab to mark done, Delete, Esc.

## API

**Views** (`View`, all `Data`):

| view | draws |
| --- | --- |
| `Text{st, s}` | one row |
| `Lines{st, ls}` | a row per string |
| `Fill{c}` | the whole area with one cell |
| `Above{top, bottom, rows}` / `Below{top, bottom, rows}` | a split: `rows` for the top, or for the bottom; the other gets the rest |
| `Beside{left, right, cols}` / `After{left, right, cols}` | a split: `cols` for the left, or for the right |
| `Boxed{title, child}` | a border with the title on it; the child inside |
| `Menu{items, sel, top}` | a row per item from item `top`; item `sel` inverse |
| `Input{text, cursor}` | one row; the cell at `cursor` inverse |
| `Progress{done, total, st}` | one row, filled `done / total` of the width |

A widget's rows are cut or padded to the area it gets; nothing overflows.
`Style{fg, bg, bold}` uses 256-color codes, `256` for the terminal's default;
`Style.plain()`, `Style.fg(c)`, `Style.bold(c)`, `Style.inverse()`.

**Frames**: `render(v, w, h)` gives `List<List<Cell>>`, `h` rows of `w`;
`Frame.show(f)` is the string that paints it all, `Frame.diff(next, prev)` the
string that paints what changed, row by row.

**The loop**: `Tui.run(~M, ~Tui{view, update}, m0, ms)` with
`view: M -> View` and `update: List<Key> -> M -> Maybe<M>`. Each turn: the
terminal's size, `view` of the state rendered to it, the diff written, the
keys read within `ms` (an empty list on a timeout: a tick), `update`, which
answers the next state or `None` to quit. `Tui.fold(~M, ~step, ks, Some{m})`
folds a `step: M -> Key -> Maybe<M>` over the keys, for updates that treat
keys one at a time. Both are templates over closed defs, as `App.run` is:
that is what lets `view` and `update` be called every turn (a closure is
affine, one call). Since a template's function argument must take affine
parameters, a `step` or `view` that uses its state twice is a `+m` def
wrapped in an affine one (`step.at`/`step` in the demos).

The consumer imports `tty.bend` itself to name the keys (`T.Up{}`): an
alias is per file.

## Laws

| law | claim |
| --- | --- |
| `fit_len(w, cs)` | `length(fit(w, cs)) == w` |
| `fit_rows_len(h, w, rows)`, `fit_rows_cols(h, w, rows)` | `h` rows; every one of `w` cells |
| `render_rows(v, w, h)` | `length(render(v, w, h)) == h`, for every view |
| `render_cols(v, w, h)` | every row of `render(v, w, h)` has `w` cells, for every view |
| `diff_self(f)` | `Frame.diff(f, f) == ""` |

`fit` and `fit_rows` recurse on the size, so each count is one induction on
it, and `render` is `fit_rows` of `draw`, so its laws are those applied: the
theorem about every widget costs two lines. `diff_self` is reflexivity of the
comparisons from `U32.cmp` up (`u32_cmp_refl` from
[bend-lemmas](https://github.com/caiodomingues/bend-lemmas)) and a join of
empty strings. `bend PROOF.bend` prints `All terms check.`

## Lanes

- **Native** (`bend demos/todo.bend -o todo`): verified on Linux with clang
  14 under a 40x12 pty — typing, Enter, arrows, Tab, Delete, Esc; every row
  exactly 40 cells; the dashboard ticking at 100 ms; the alternate screen
  and raw mode left as found.
- **JS** (`bend demos/todo.bend`): the same, verified under a pty — but only
  from a checkout whose directories have no `-`: the JS emitter keeps a
  hyphen from a module path in the identifiers it generates
  (`$$bend-tty$tty$Tty$raw$`), which is a syntax error. Native is fine.
  Upstream `bend2/comp.ts`, `js_sat`, as of 2.0.18.
- The checker reports the template instances (`Tui.run`, `Tui.loop`,
  `Tui.fold`) as "3 unsafe annotations": that is how it counts templates.

Not in v1: mouse, wide characters (one cell is one column), a resize signal
(the size is read each turn instead), a cursor for `Input` (it is drawn
inverse, not moved).

## Run

    bend tui.bend                        # renders a sample as text
    bend PROOF.bend                      # All terms check.
    bend demos/todo.bend -o todo && ./todo
    bend demos/dashboard.bend -o dashboard && ./dashboard

Depends on `../bend-tty` (effects and keys) and, for the proofs,
`../bend-lemmas` (one lemma): clone the three side by side.
