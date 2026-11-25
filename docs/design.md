# Design: inline rendering, layout and CLI components

A sketch for review before any code. Names are proposals. `C` is bend-tty's
`color.bend`, `X` its `text.bend`, `T` its `tty.bend`.

## Cells

A cell holds a grapheme cluster, not a code point, so CJK and emoji line up.
A wide cluster takes two cells: the cluster, then `Cell.Pad`. A row is
still exactly `w` cells, so `fit`'s laws stay structural. `fit` also blanks
a wide cluster cut at the right edge, so a row never prints `w + 1` columns.

```python
type Look is Data:
  Look{st: C.Style, link: String}             # link: "" for none (OSC 8)

type Cell is Data:
  Cell.Of{g: String, look: Look}               # one cluster from X.Ansi.units
  Cell.Pad{}                                   # the second column of a wide one; writes nothing
```

The style is bend-tty's `C.Style`, not the current `Style{fg, bg, bold}` on
256 colours. It is painted when the frame becomes a string, at the stream's
`C.Level`, so `NO_COLOR` and pipes get plain text with no change to a view.
`Tui.run` paints at the terminal's level too.

## Text

```python
type Span is Data:
  Span.S{s: String}                            # plain text
  Span.In{st: C.Style, kids: List<&2, Span>}   # chalk-like: inner set parts win, unset ones inherit
  Span.Link{url: String, kids: List<&2, Span>}

type Wrap is Data:
  Wrap.Word{}                                  # wrap-ansi, hard: true (Ink's default)
  Wrap.Hard{}                                  # wrap-ansi, wordWrap: false
  Wrap.Cut{at: X.Cut}                          # cli-truncate at End, Start or Middle
```

The spans are flattened to clusters, each with its look. Wrap and truncate
run bend-tty's `X.Ansi.wrap` and `X.Ansi.truncate` on the plain text, then
the looks are laid back on by walking both cluster lists. The output is a
subsequence of the input plus line breaks, tab spaces and the ellipsis, so
one pass places them. No wrap logic is written twice.

## Views

The current views stay, for full-screen apps. New ones, after Ink's Box:

```python
type Size is Data:
  Size.Auto{}                                  # the content's size
  Size.Cols{n: Nat}                            # fixed
  Size.Pct{p: Nat}                             # percent of the parent

type Justify is Data:   # main axis
  Justify.Start{}  Justify.End{}  Justify.Center{}  Justify.Between{}  Justify.Around{}  Justify.Evenly{}

type Align is Data:     # cross axis
  Align.Start{}  Align.End{}  Align.Center{}  Align.Stretch{}

type Line is Data:      # border glyphs, as cli-boxes
  Line.Single{}  Line.Round{}  Line.Double{}  Line.Bold{}

type View is Data:
  # ...the current ones...
  View.Txt{spans: List<&2, Span>, wrap: Wrap}
  Row{kids: List<&2, Flex>, gap: Nat, justify: Justify, align: Align}
  Col{kids: List<&2, Flex>, gap: Nat, justify: Justify, align: Align}
  Pad{t: Nat, r: Nat, b: Nat, l: Nat, child: View}
  Margin{t: Nat, r: Nat, b: Nat, l: Nat, child: View}
  Border{line: Line, st: C.Style, title: List<&2, Span>, child: View}   # title on the top edge
  Sized{w: Size, h: Size, child: View}

type Flex is Data:
  Flex{v: View, grow: Nat, shrink: Nat, basis: Size}   # Flex.of(v) = grow 0, shrink 1, Auto, as Ink
```

Layout is one pass per container: fixed and percent sizes, then content
sizes (`View.width(v)`, the natural width, and `View.height(v, w)`, the
height at a width), then the free space shared by `grow`, or the overflow
taken back by `shrink`, in proportion. Then `justify` and `align`.
`render(v, w, h)` is unchanged in type, and its laws, `h` rows of `w`
cells, cover every new view.

## Components

Plain functions to `View`, and small state types with a key step, so a
program composes them:

```python
Spinner.dots(tick: Nat) -> Span           # ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏, a frame per 80 ms tick
Spinner.clack(tick: Nat) -> Span          # ◒◐◓◑, magenta
Bar.view(done: Nat, total: Nat, eta: String) -> View   # ████░░░░ 61%  eta from the program
Badge.view(st: C.Style, s: String) -> Span
Link.view(url: String, text: String) -> Span           # OSC 8; text (url) where off
Note.view(title: String, body: List<&2, String>) -> View
Table.view(head: List<&2, String>, rows: List<&2, List<&2, String>>) -> View

type Task is Data:
  Task{title: String, state: Task.State, out: String, kids: List<&2, Task>}
type Task.State is Data:   # pending, running, done ✓, failed ✗, skipped ↓
  Task.Wait{}  Task.Run{}  Task.Ok{}  Task.Fail{msg: String}  Task.Skip{msg: String}
Task.view(tick: Nat, t: Task) -> View     # listr2's look; a done parent collapses unless a kid failed

type Select is Data:
  Select{title: String, items: List<&2, String>, sel: Nat, marks: List<&2, Bool>, multi: Bool}
Select.view(s: Select) -> View
Select.key(s: Select, k: T.Key) -> Answer<Select, Nat>   # Answer.More{s}, Answer.Done{a}, Answer.Cancel{}
# Confirm, Input: the same shape; Input asks the renderer for a real cursor
```

## Inline rendering

What a CLI frame is: lines that are printed once and never redrawn, a live
view below them, and where the real cursor goes, if anywhere.

```python
type Screen is Data:
  Screen{done: List<&2, View>, live: View, cursor: Maybe<&2, Pos>}

# the renderer's memory, pure; Inline.draw answers what to write and the next one
type Inline is Data:
  Inline{tty: Bool, level: C.Level, w: Nat, rows: Nat, prev: List<&2, List<&2, Cell>>, printed: Nat}

def Inline.draw(st: Inline, s: Screen) -> Inline.Out   # Out{text: String, next: Inline}
def Inline.end(st: Inline, s: Screen) -> String
```

On a terminal (`tty`), the cursor rests on the row below the frame. A draw:

1. Done views past `printed`: move up over the frame, erase down, write
   them, then the whole live frame.
2. Otherwise: move up, rewrite only the rows that changed, step over the
   others, and erase below a frame that shrank.
3. A frame taller than the terminal shows its bottom `rows - 1` rows.
4. All of it inside `Tty.sync`, the cursor hidden; if `cursor` is set, it
   moves there and shows.

`Inline.end` writes the final frame whole when it was clipped, then leaves
the cursor below it, visible.

Without a terminal (`tty` is `False`, or `CI` is set, as Ink): done views
are written as they come, the live frame never, the final frame once, and no
cursor escape at all. Spinners have no frames there, and a task list prints a
line per finished task.

## Laws

| law | claim |
| --- | --- |
| `render_rows`, `render_cols` | every view, the new ones too, renders to `h` rows of `w` cells |
| `fit_wide` | `fit` never ends a row on a wide cluster without its `Cell.Pad` |
| `inline_same` | drawing the same screen twice: the second draw writes `""` |
| `static_once` | a draw writes the done views past `printed`, and sets `printed` to their count, so each is written once |
| `pipe_plain` | with no terminal, a draw's text is the new done lines joined by `\n`: no cursor movement |
| `cell_safe` | no cluster in a cell holds a control character, so no text moves the cursor |

## The loops

`Tui.run` stays as it is: full screen, the alternate screen.

```python
type Ev<Msg: Data> is Data:
  Ev.Keys{ks: List<&2, T.Key>}  Ev.Tick{}  Ev.Msg{m: Msg}  Ev.Done{}   # Done: the work ended

type Cli<M: Data, Msg: Data> is Type:
  Cli{view: M -> Screen, update: Ev<Msg> -> M -> Maybe<&2, M>, keys: M -> Bool}

def Cli.run(~M, ~Msg, ~app: Cli<M, Msg>, m0: M, work: Chan(Msg) -> IO(Unit), tick: U32) -> IO(M)
def Cli.post(-Msg, ch: Chan(Msg), m: Msg) -> IO(Unit)
```

`work` runs as its own computation and posts messages; the loop takes the
next one within `tick` ms, or a `Tick`, folds it into the state and draws.
Raw mode is on only while `keys(m)` is true. Ctrl-C ends the loop, restores
the cursor and the mode, and answers the state as it was. Prompts are
`Cli.run` with no work:

```python
Prompt.select(title, items) -> IO(Maybe<&2, Nat>)       # None: cancelled
Prompt.confirm(title, dflt) -> IO(Maybe<&2, Bool>)
Prompt.text(title, placeholder) -> IO(Maybe<&2, String>)
```

## The north-star, sketched

```python
type St is Data:
  St{log: List<&2, View>, done: Nat, total: Nat, tick: Nat, end: Bool}

type Msg is Data:
  Msg.Line{v: View}  Msg.Got{n: Nat}

def view(s: St) -> U.Screen:
  match s:
    case St{log, done, total, tick, end}:
      U.Screen{log, Live.of(end, tick, done, total), None{}}

def update(e: R.Ev<Msg>, s: St) -> Maybe<&2, St>:
  ...   # Line appends to log, Got sets done, Tick counts, Done ends

def work(ch: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    R.Cli.post(ch, Msg.Line{ok("resolved 0.4.0 (engine 0.4.0, Bend 2.0.40, Bun 1.4.5)")})
    ...   # the download, posting Got as bytes arrive

def main() -> IO(Unit):
  do IO<Unit>:
    s : St <- R.Cli.run(~St, ~Msg, ~R.Cli{view, update, no_keys}, St.new(), work, 80)
    IO.pure(Unit, Unit{})
```

## Order of work

1. Cells as clusters, `C.Style`, `Inline.draw`/`end` with the static
   region, and `Cli.run`: a demo with static lines and a live line.
2. `View.Txt` with spans and wrap; then Row, Col, Pad, Margin, Border,
   Sized.
3. Spinner, Bar, Task; `demos/install.bend` and `demos/tasks.bend`.
4. Select, Confirm, Input with the real cursor; `demos/prompts.bend`.
5. Table, Badge, Link, Note.

Each step proves its laws, runs on both lanes, and keeps `todo`,
`dashboard` and `life` running.
