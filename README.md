# bend-tui

Terminal interfaces for [Bend](https://bend-lang.com) 2, on
[bend-tty](https://github.com/caiodomingues/bend-tty). A `View` is a tree of
widgets; `render` lays it out into a frame of cells. Two loops draw it:
`Tui.run`, a full-screen app on the alternate screen, and `Cli.run`, a
command-line flow drawn inline under what the program printed, as Ink
does. Requires Bend 2.0.40, as bend-tty does, and bend-tty's
`Tty.inline` (branch `feat/inline-guard` until it is merged).

Some facts about every frame are theorems, not tests: it has exactly `h`
rows, and every row has exactly `w` cells, for every view, size and state
(`render_rows`, `render_cols`); a frame diffed against itself writes
nothing (`diff_self`); an inline screen drawn again unchanged writes
nothing (`inline_same`), each line above the live frame is written once
(`static_once`), and with no terminal a draw writes only those lines,
never a cursor movement (`pipe_plain`).

```python
import Base
import ../../bend-tty/tty.bend as T
import ../tui.bend as U
import ../run.bend as R

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
    U.View.Text{U.Style.plain(), Nat.show(Nat.mod(n, period)) ++ " / " ++ Nat.show(period)},
    U.Progress{Nat.mod(n, period), period, U.Style.fg(color)},
    1n}}

def view.at(+n: Nat) -> U.View:
  U.Below{
    U.Split{panel("cpu", n, 40n, 42), U.Split{panel("mem", n, 90n, 214), panel("disk", n, 200n, 203), 1n, 2n}, 1n, 3n},
    U.Boxed{"log", U.Lines{U.Style.fg(245), ["turn " ++ Nat.show(n), "Esc quits"]}},
    4n}

def view(n: Nat) -> U.View:
  view.at(n)

def main() -> IO(Unit):
  R.Tui.run(~Nat, ~U.Tui{view, update}, 0n, 100)
```

That is `demos/dashboard.bend`. `demos/todo.bend` is a list with an input:
type and Enter to add, Up/Down, Tab to mark done, Delete, Esc. Ctrl-C quits
any `Tui.run`. `demos/life.bend` is Conway's Game of Life on a 60x16 grid, a
generation per tick and every row in its own color: Space pauses, r reseeds,
Esc quits. `demos/steps.bend` is a `Cli.run`: work that posts lines and
progress, the lines printed once above a live spinner and bar, a summary
left at the end; piped, the lines and the summary alone.
`demos/install.bend` is what `ogw install` will look like:

    ◇ ogw install 0.4.0
    ✓ resolved 0.4.0 (engine 0.4.0, Bend 2.0.40, Bun 1.4.5)
    ✓ downloaded 41.2 MB in 3.0 s
    ◓ verifying sha256 ████████████░░░░░░░░ 60%

and, when it ends, `└ installed in ~/.ogw/versions/0.4.0` in the live
line's place. `demos/tasks.bend` is a listr2 task list with nested
tasks, one failing; each top task is printed once as it finishes.
`demos/prompts.bend` asks what `ogw new` will ask: a template (select),
features (multi-select), whether to install (confirm) and a name (text,
placeholder `my-game`), then prints a note with the next steps; a cancel
ends the flow.

## API

**Cells and looks.** A cell holds a grapheme cluster, as bend-tty's
`X.Ansi.units` cuts a string, so CJK and emoji line up: a cluster two
columns wide takes two cells, the cluster (`Cell.Of{g, look}`) and a
`Cell.Pad{}`, and `fit` blanks one whose second column is cut off. A look
is `Look.Of{st, link}`: bend-tty's `C.Style` (colours at any level,
bold, dim, italic, underline, inverse, hidden, strike) and an OSC 8 link
(`""` for none). A control character in a string (below 32, or 127 to
159) is drawn as a blank, so text cannot move the cursor or start an
escape. `Style.plain()`, `Style.fg(c)` and `Style.bold(c)` (a 256-colour
code) and `Style.inverse()` build `C.Style`s.

**Views** (`View`, all `Data`):

| view | draws |
| --- | --- |
| `View.Text{st, s}` | one row |
| `Lines{st, ls}` | a row per string |
| `Fill{c}` | the whole area with one cell |
| `Above{top, bottom, rows}` / `Below{top, bottom, rows}` | a split: `rows` for the top, or for the bottom; the other gets the rest |
| `Beside{left, right, cols}` / `After{left, right, cols}` | a split: `cols` for the left, or for the right |
| `Split{left, right, num, den}` / `Stack{top, bottom, num, den}` | a split by ratio: `w * num / den` columns for the left, `h * num / den` rows for the top |
| `Boxed{title, child}` | a border with the title on it; the child inside |
| `Menu{items, sel}` | a row per item, item `sel` inverse, scrolled so that it is on screen |
| `Input{text, cursor}` | one row; the cluster at `cursor` inverse |
| `Progress{done, total, st}` | one row, filled `done / total` of the width |
| `View.Txt{spans, wrap}` | styled text: `Wrap.Word{}` and `Wrap.Hard{}` wrap it to the width (bend-tty's `Ansi.wrap`), `Wrap.Cut{at}` keeps one row with an ellipsis (`Ansi.truncate`, `X.Cut.End{}`, `Start{}`, `Middle{}`); a `\n` breaks a line |
| `Row{kids, gap, justify, align}` / `Col{kids, gap, justify, align}` | flexbox on one axis: each `Flex{v, grow, shrink, basis}` gets its basis (`Size.Auto{}` its content, `Size.Cols{n}`, `Size.Pct{p}` of the parent), then a share of the free space by `grow` or of the overflow by `shrink` times basis; `gap` between; `Justify` Start, End, Center, Between, Around, Evenly; `Align` Start, End, Center, Stretch on the cross axis |
| `Pad{t, r, b, l, child}` | blank rows and columns around the child (`View.pad(n, v)`; `View.margin` is the same outside a border) |
| `Border{line, st, title, child}` | a border in `Line.Single{}`, `Round{}`, `Double{}` or `Bold{}` (cli-boxes' glyphs) and a style, the title spans on the top edge |
| `Sized{w, h, child}` | the child at a size of its own: `Size.Cols{n}`, `Size.Pct{p}`, or `Size.Auto{}` |

Spans are chalk-like: `Span.S{s}` is text, `Span.In{st, kids}` styles what
it holds, an inner style's set parts winning and its unset ones inherited,
and `Span.Link{url, kids}` makes it a link. Wrapping and truncation run on
the plain text and the looks are laid back on cluster by cluster, so a
wrapped or cut line keeps its colours and CJK and emoji measure as
string-width says. Shorthands with Ink's defaults: `txt(s)`, `spans(sp)`,
`Span.of(st, s)`, `Flex.of(v)` (grow 0, shrink 1, auto),
`Flex.grow(v)`, `Row.of(kids)`, `Col.of(kids)` (no gap, start, stretch).

**Components**, functions to views and small state types:

| component | what |
| --- | --- |
| `Spinner.dots(tick)`, `Spinner.clack(tick)` | cli-spinners' `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` and clack's `◒◐◓◑`, a frame per tick (both are drawn at 80 ms) |
| `Meter{done, total, on, off}` | a view: one row, `done / total` of it `█` in `on`, the rest `░` in `off` |
| `Bar.view(label, done, total, cols, eta)` | a label, a bar of up to `cols` columns that gives way first when the row is narrow, the percentage, and an ETA string the program works out |
| `Task{title, state, out, kids}` | listr2's task list: `Task.Wait{}` dim `◼`, `Task.Run{}` a yellow spinner (`❯` for a parent), `Task.Ok{}` green `✓`, `Task.Fail{msg}` red `✗` and `› msg`, `Task.Skip{msg}` yellow `↓`; `Task.view(tick, ts)` shows subtasks two columns in while their parent runs or when one failed, and a running task's `out` under it after `›`; `Task.put(ts, path, edit)` sets a state (`Task.To{st}`) or an output line (`Task.Say{s}`) at a path of sibling indexes |
| `Badge.view(st, s)`, `Link.view(url, text)` | spans: ` s ` inverse in `st`; an OSC 8 link, `text (url)` where links are off |
| `View.Edit{chars, cursor, placeholder}` | a view: a text field's row; the character at `cursor` (a blank past the end) is a `Cell.At`, where an inline frame puts the terminal's real cursor; while empty, the placeholder dim with the cursor on its first character |
| `Table.view(head, rows)` | lipgloss' table: a normal border, the header bold over a rule, each column as wide as its widest cell by display width |
| `Note.view(title, body)` | @clack/prompts' note: a green `◇` and the title on the top edge, the lines inside, closed on the rail with `├` |
| `Pick`, `Yes`, `Field` | the state of a select (single or multi), a confirm and a text input, each with `.key(p, k)`, `.view(p)` and `.answer(p)`, drawn as @clack/prompts draws them: `◆` open, `◇` answered, `■` cancelled; `●`/`○` radios, `◼`/`◻` checkboxes, `● Yes / ○ No`; an answered prompt collapses to its title and its answer, dim |

**Prompts** (`run.bend`), one call a question, each a `Cli.run` with raw
mode on while it is open: `Prompt.select(title, items)` answers
`Maybe<Nat>`, `Prompt.multi(title, items)` `Maybe<List<Nat>>` (Space
marks), `Prompt.confirm(title, dflt)` `Maybe<Bool>` (y and n answer at
once), `Prompt.text(title, placeholder)` `Maybe<String>` (the placeholder
when nothing is typed; Left, Right, Home, End, Backspace, Delete). Up/Down
or k/j move, Enter answers, and Esc, Ctrl-C or the end of the input
cancels: `None`, the prompt left with `■` and its value struck through.
`Cli.print(v)` writes a view once, at the terminal's width and the
stream's colour level, for what a CLI prints before or after its loops.

A widget's rows are cut or padded to the area it gets; nothing overflows.
`View.height(v, w)` is the rows a view takes at width `w` when nothing
bounds it, which is the height of an inline frame.

**Frames**: `render(v, w, h)` gives `List<List<Cell>>`, `h` rows of `w`.
A `Pen{level, links}` is how a stream shows looks: its `C.Level` (none
for `NO_COLOR` or a pipe) and whether links are OSC 8 or spelled out.
`Frame.show(pen, f)` is the string that paints it all, `Frame.diff(pen,
next, prev)` the string that paints what changed, row by row.

**The full-screen loop** (`run.bend`): `Tui.run(~M, ~Tui{view, update},
m0, ms)` with `view: M -> View` and `update: List<Key> -> M -> Maybe<M>`.
Each turn: the terminal's size, `view` of the state rendered to it, the
diff written (the whole frame after a resize), the keys read within `ms`
(an empty list on a timeout: a tick), `update`, which answers the next
state or `None` to quit; Ctrl-C quits before `update` sees it. A read that
ends in a lone ESC gets 100 ms more before decoding, so an arrow that
arrives in two pieces (SSH) is an arrow; a lone Esc key is seen 100 ms
late. `Tui.fold(~M, ~step, ks, Some{m})` folds a `step: M -> Key ->
Maybe<M>` over the keys, for updates that treat keys one at a time.

**Inline screens.** A `Screen{done, live}` is what a CLI shows: `done`
views, printed once above, and the `live` view below them, redrawn. The
pure renderer is `Inline{tty, pen, w, rows, prev, printed}`:
`Inline.draw(st, screen)` answers `Inline.Out{text, next}`. On a terminal
the cursor rests at the start of the row below the frame; done views not
yet written go above a whole new frame, or else the frame is redrawn from
its first changed line, inside synchronized output; a frame taller than
the terminal shows its last `rows - 1` lines. When the frame holds a
`Cell.At`, the terminal's cursor is shown there, and parked back below
the frame before anything else is written; when no line changed and the
cursor stays put, a draw writes nothing. `Inline.end(st, screen)`
writes the last done views and the whole final frame, unclipped, so the
scrollback holds all of it. With no terminal, done views are written as
they come, the live frame once at the end, and nothing moves the cursor.

**The inline loop** (`run.bend`): `Cli.run(~M, ~Msg, ~Cli{view, update,
keys}, m0, work, tick)` answers the last state. `view: M -> Screen`,
`update: Ev<Msg> -> M -> Step<M>` (`Step.Go{m}` or `Step.End{m}`),
`keys: M -> Bool`. `work: Chan(Ev<Msg>) -> IO(Unit)` runs as its own
computation and posts messages with `Cli.post(Msg, ch, m)`; when it
returns, the loop gets `Ev.Done`. Each turn takes one event: the next
message, or, while `keys(m)` holds, the keys of a read (raw mode is on
only then), or `Ev.Tick` when nothing came within `tick` ms. Ctrl-C is
`Ev.Cancel`, and the loop stops after it whatever `update` answers. The
output is live when stdout is a terminal, `TERM` is not `dumb` and `CI`
is unset (as Ink decides); colours follow bend-tty's `Level` alone, so
`NO_COLOR` and pipes get plain text and `FORCE_COLOR` gets colours with
no cursor movement. While it runs, `Tty.inline` makes the exit and, on the
native lane, SIGINT, SIGTERM and SIGHUP show the cursor again.

Loops are templates over closed defs, as `App.run` is: that is what lets
`view` and `update` be called every turn (a closure is affine, one call).
Since a template's function argument must take affine parameters, a
`step` or `view` that uses its state twice is a `+m` def wrapped in an
affine one (`step.at`/`step` in the demos), and `work` takes its channel
affine and rebinds it (`+ch = c`) to post more than once.

The library is two files. `tui.bend` is pure: the views, `render`, the
frames, the inline renderer, the app types, everything the proofs need.
`run.bend` holds the loops, which run bend-tty's effects (`tty_io.bend`);
a proof may import no foreign code, so the split keeps `PROOF.bend` on the
pure file. A program imports `tui.bend` and `run.bend`, and `tty.bend` to
name the keys (`T.Up{}`): Bend does not re-export imports, and an alias is
per file.

## Laws

| law | claim |
| --- | --- |
| `fit_len(w, cs)` | `length(fit(w, cs)) == w` |
| `fit_rows_len(h, w, rows)`, `fit_rows_cols(h, w, rows)` | `h` rows; every one of `w` cells |
| `render_rows(v, w, h)` | `length(render(v, w, h)) == h`, for every view |
| `render_cols(v, w, h)` | every row of `render(v, w, h)` has `w` cells, for every view |
| `diff_self(p, f)` | `Frame.diff(p, f, f) == ""` |
| `lines_first_same(ls, i)` | two lists of the same lines have no first difference |
| `inline_same(st, s)` | drawing a screen again, unchanged, writes `""`, on a terminal or not |
| `static_once(st, done, more, live)` | after a draw, the done views left to write are exactly those added since |
| `pipe_plain(prev, fresh, next)` | with no terminal, `Inline.write` writes the new done lines joined by line breaks, nothing else |
| `pipe_draw(..)`, `pipe_end(..)` | with no terminal, what `Inline.draw` writes is the done lines not yet written, joined by line breaks, and what `Inline.end` writes is those and the whole final frame: never a cursor movement, for every screen |
| `pct_halves` | a percent basis is a share of the whole row for every child: two halves of 20 columns are 10 and 10 |

`fit` and `fit_rows` recurse on the size, so each count is one induction on
it, and `render` is `fit_rows` of `draw`, so its laws are those applied: the
theorem about every widget costs two lines. `diff_self` is reflexivity of
the comparisons, from `U32.cmp` and `Bool.cmp` up through colours, styles,
looks and cells (`u32_cmp_refl`, `bool_cmp_refl` from
[bend-lemmas](https://github.com/caiodomingues/bend-lemmas)), and a concat
of empty strings. `inline_same` is a drop of the done list by its own
length, which is empty, `lines_first_same`, and the cursor's key compared
with itself; `static_once` is the drop of a longer list. `bend PROOF.bend`
prints `ALL PROOFS CHECK`; it imports `tui.bend` alone, since importing
`run.bend`, or any file with foreign code, fails the verdict. `bend
LAWS.bend` states the laws without their proofs, so it prints `SOME PROOFS
FAIL` with its TODOs.

## Lanes

Everything below ran on Linux (WSL, x86_64) with Bend 2.0.40, under a pty
driven by a script and read back through a small terminal emulator (no
reflow on resize), not in a real terminal; macOS was not tried.

- **Native** (`bend demos/todo.bend -o todo`): typing (a CJK character
  too), Enter, arrows, Tab and Esc in the todo, the dashboard ticking at
  100 ms and quitting on Ctrl-C, Space and r in life, each quitting with
  exit 0 and the cursor shown; SIGTERM on the todo leaves the main screen
  and the cursor. `demos/steps.bend`: each line above written once, the
  live line redrawn alone (up one row, erase down), the summary left with
  the cursor shown; Ctrl-C and SIGTERM mid-task end it with the cursor
  shown; a resize from 80 to 30 columns mid-run redraws at 30. A live frame
  of 30 lines in 24 rows shows its last 23, then all 30 once at the end.
  `demos/install.bend` at 40, 80 and 120 columns: at 80 and 120 the lines
  above and the bar line as in the sample; at 40 a long line wraps under
  its text, not under its mark, and the bar shrinks before the percentage
  does. Under a pty, `NO_COLOR=1` moves the cursor and writes no SGR;
  `CI=1` and `TERM=dumb` write no cursor movement and no SGR;
  `FORCE_COLOR=3 | cat` writes colours and no cursor movement; piped, no
  ESC byte. `demos/tasks.bend`: the running parent with `❯`, its subtasks
  in, the running one's output under it; piped, a block per top task as it
  finishes. `demos/prompts.bend` driven by keys: Down and Enter, Space,
  Down, Down, Space and Enter, `n`, then `games`, Backspace, Left, `X` and
  Enter answer platformer; physics, networking; No; gamXe, each left
  collapsed; the real cursor sits on the placeholder's first character,
  then after `gamX`; Ctrl-C in the first prompt and Esc in the second end
  the flow with `■` and `└  cancelled`; with stdin at `/dev/null` the first
  prompt cancels; under `NO_COLOR=1` the multi-select's row under the
  cursor shows `›`. A link is OSC 8 under a pty and `text (url)` piped. A
  loop ended by a key while its work still posts exits 0.
- **JS** (`bend demos/todo.bend -o todo.js` and `bun todo.js`), bun 1.4.2:
  the same runs for the todo, dashboard, life, steps, install (80 columns
  and the four environments above), tasks and prompts, with the same
  results, and the same bytes for `steps` and `install`. Two differ: a
  resize is not seen (bun updates `process.stdout.columns` on its own event
  loop, which the runtime never runs, so the size stays the first one), and
  a signal ends the program with the terminal as it was (bend-tty hooks
  none on this lane, for the same reason): Ctrl-C during a `Cli.run` task
  leaves the cursor hidden (`tput cnorm` shows it), and SIGTERM on a
  `Tui.run` leaves the alternate screen and raw mode. bun, not node:
  bend-tty's read reaches libc through `bun:ffi`.
- A file that runs effects fails the verdict by design: `bend run.bend
  --check-only` and `bend demos/todo.bend --check-only` print `SOME PROOFS
  FAIL` and list the defs that rely on foreign code. For those the gate is
  the build.

Not in v1: mouse, a resize signal (the size is read each turn instead), a
real cursor in full-screen apps (`Input` is drawn inverse there; the
inline `View.Edit` moves it), editing by grapheme cluster in `Field` (it
edits code points), a window for long selects (every item is shown), a
sequence split across the `max` of a read, flex wrapping onto more lines,
`min-content` sizes (a child shrinks to zero columns, not to its longest
word). With stdout not a terminal, a prompt is not drawn while it is open
(the loop draws nothing live there) but still reads keys; its summary comes
at the end. Under `NO_COLOR`, a full-screen `Menu` or `Input` loses its
inverse cell, the only thing that marks the selection.

## Run

    bend tui.bend                        # renders a sample as text
    bend PROOF.bend                      # ALL PROOFS CHECK
    bend LAWS.bend                       # SOME PROOFS FAIL: the laws as TODOs
    bend demos/todo.bend -o todo && ./todo
    bend demos/dashboard.bend -o dashboard && ./dashboard
    bend demos/life.bend -o life && ./life
    bend demos/steps.bend -o steps && ./steps     # and ./steps | cat
    bend demos/install.bend -o install && ./install
    bend demos/tasks.bend -o tasks && ./tasks
    bend demos/prompts.bend -o prompts && ./prompts

Depends on `../bend-tty` (`tty.bend`, `color.bend` and `text.bend`, and
`tty_io.bend` for the effects) and, for the proofs, `../bend-lemmas`:
clone the three side by side.
