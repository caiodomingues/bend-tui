# Grounding

What the libraries bend-tui follows do, what it copies from each, and where
it differs. Every source below was **read in this session** (2026-11-24),
from shallow clones at the commits listed; nothing was installed or run. A
fact marked *remembered* was not found in those clones.

| source | version | commit |
| --- | --- | --- |
| [ink](https://github.com/vadimdemedes/ink) | 8.0.0 | `011b1d1` |
| [log-update](https://github.com/sindresorhus/log-update) | 8.0.0 | `1ca3b06` |
| [ink-spinner](https://github.com/vadimdemedes/ink-spinner) | 5.0.0 | `87a33c0` |
| [ink-select-input](https://github.com/vadimdemedes/ink-select-input) | 6.2.0 | `6cde55c` |
| [ink-text-input](https://github.com/vadimdemedes/ink-text-input) | 6.0.0 | `4ac429c` |
| [cli-spinners](https://github.com/sindresorhus/cli-spinners) | 3.4.0 | `c5f18f6` |
| [cli-boxes](https://github.com/sindresorhus/cli-boxes) | | `127269a` |
| [listr2](https://github.com/listr2/listr2) | 11.4.1 | `4ad3142` |
| [clack](https://github.com/bombshell-dev/clack) | prompts 1.9.0, core 1.6.0 | `549f7df` |
| [vercel](https://github.com/vercel/vercel) `packages/cli` | 65.4.0 | `155eacf` |
| [bubbletea](https://github.com/charmbracelet/bubbletea) | v2 | `b78ae0e` |
| [ultraviolet](https://github.com/charmbracelet/ultraviolet) | | `8ecbcf0` |
| [bubbles](https://github.com/charmbracelet/bubbles) | v2 | `0c1a491` |
| [lipgloss](https://github.com/charmbracelet/lipgloss) | v2 | `7d3aa33` |
| [ratatui](https://github.com/ratatui/ratatui) | | `ae8c0e0` |

## Inline rendering

**Ink** lays the tree out with Yoga at the terminal's width and an unbounded
height, so a frame is as tall as its content (`ink.tsx` 441-453). `Output`
is a grid of styled cells; each row is serialised with minimal SGR changes
and `trimEnd`-ed (`output.ts` 26-54, 465-503). Ink ships its own
`log-update.ts`, not the npm package. Its default writer rewrites the whole
frame: `eraseLines(min(previousLineCount, rows))` then the new text, and
nothing at all when the text is unchanged (`log-update.ts` 37-145). An
opt-in incremental writer moves up over the frame and rewrites only the
changed lines (147-355). A frame is written with a trailing `\n`, so the
cursor rests on the row below it. At unmount, `log.done()` erases nothing
and shows the cursor: the final frame stays in the scrollback (`ink.tsx`
1389-1530). Writes are throttled to 30 fps, leading and trailing. A frame
taller than the terminal is written whole and the viewport is cleared with
`cursorTo(0,0)` + erase-down before each later frame, never `CSI 3J`
(`ink.tsx` 75-135).

**log-update** (sindresorhus) is a different algorithm: it hard-wraps the
frame to the width, keeps only its last `rows` lines (`fitToTerminalHeight`,
`index.js` 18-61), diffs the common prefix and suffix against the previous
frame and patches the middle, inside synchronized output (`?2026`).

**Bubble Tea** v2 (`cursed_renderer.go`, diffing in ultraviolet's
`TerminalRenderer`) moves the cursor relatively, repaints only the rows
that changed and diffs cells within a row. A shrinking frame erases below
its new last row. A frame taller than the terminal keeps its **bottom**
`height` rows (`cursed_renderer.go` 350-389, pinned by
`TestCursedRendererDrawsChangedEmptyAndTallViews`). Updates are wrapped in
synchronized output.

**clack** diffs lines against the previous frame: one changed line is
rewritten alone, several are erased from the first changed line down and
rewritten.

**ratatui** diffs two cell buffers and emits only the changed cells
(`MoveTo` only when the cursor is not already there). `Viewport::Inline(h)`
reserves `h` rows under the cursor by printing newlines.

*Copied*: Ink's model, a frame as tall as its content under what was
printed, with the cursor parked on the row below it and the final frame left
in the scrollback with the cursor shown. From Bubble Tea, clack and Ink's
incremental writer: rewrite only the rows that changed, erase below a frame
that shrank, wrap each write in `Tty.sync`. From Bubble Tea and log-update:
a frame taller than the terminal shows its bottom rows while it is live,
because rows that scrolled into the scrollback cannot be reached by moving
up.

*Different*: no throttle in the renderer; the loop draws once per event, and
an unchanged frame writes nothing (a law, not an optimisation). At the end,
a frame that was clipped is written whole once, so the scrollback holds all
of it.

## The static region

**Ink's `<Static>`** renders each item once: it keeps the index of the
first item not yet written (`Static.tsx` 35-70). On a frame with new static
text Ink erases the live frame, writes the static text with a `\n`, and
writes the live frame again, inside synchronized output (`ink.tsx`
1055-1075). The static text is never touched again.

**Bubble Tea's `Println`** queues lines and writes them above the frame
before the next repaint; they are not part of the cell buffer
(`cursed_renderer.go` 818-902). **ratatui's `insert_before`** does the same
with scroll regions.

*Copied*: Ink's order, erase live, write the new static lines, write live,
and its counter of lines already written. *Different*: no scroll regions
(`DECSTBM` is not in bend-tty, and erase-then-write is what Ink ships).

## No terminal

**Ink**: `interactive = !isInCi && stdout.isTTY`, so CI wins even on a
terminal. When not interactive it writes no live frame: only new static
text as it appears, then the last frame and `\n` once at unmount, with no
escapes besides colour (`ink.tsx` 797-806, 1486-1494, 913-915). **listr2**
falls back to its `simple` renderer: one line per event (`✔ title`,
`✖ title [FAILED: msg]`). **Vercel CLI**'s spinner prints its message once
when not on a TTY. **Bubble Tea** still emits escapes into a pipe unless
told `WithoutRenderer()`. **clack** has no TTY gating in core.

*Copied*: Ink's rule, CI included. Whether colour is painted is bend-tty's
`Level` alone (`NO_COLOR`, pipes, `FORCE_COLOR`), so `FORCE_COLOR=3 | cat`
gets colours but never a cursor move, as bend-tty's `inline.bend` does.
Spinners write no frames; a task list writes one line per finished task.

## Input and raw mode

**Ink** turns raw mode on only while a `useInput` is active, reference
counted, with the real disable deferred by a microtask (`App.tsx` 390-455).
Ctrl-C (byte 3) unmounts the app and is not passed to handlers
(`exitOnCtrlC`, `App.tsx` 274-290). **Bubble Tea** v2 delivers Ctrl-C as a
key and leaves quitting to the model; SIGINT and SIGTERM are handled so a
second signal cannot skip the restore.

*Copied*: raw mode only while the view wants keys, and Ctrl-C always ends
the loop with the cursor and the mode restored (bend-tty's `Tty.raw(False)`
already shows the cursor and restores the mode on exit and on signals).

## Layout

**Ink's Box** (`styles.ts`) is Yoga flexbox: `flexDirection`, `gap`,
padding and margin per side, `justifyContent` (start, end, center,
space-between, space-around, space-evenly), `alignItems` (start, center,
end, stretch), `flexGrow` (default 0), `flexShrink` (default 1),
`flexBasis`, `width`/`height` as a number or a percent string. Borders come
from cli-boxes and have **no title** (none in `render-border.ts`). Text
`wrap` is `wrap` (wrap-ansi, `hard: true`), `hard`, or `truncate-end`,
`truncate-middle`, `truncate-start` (cli-truncate) (`wrap-text.ts` 15-90).

**cli-boxes**: single `┌─┐│┘└`, round `╭─╮│╯╰`, double `╔═╗║╝╚`, bold
`┏━┓┃┛┗`. Lip Gloss's normal, rounded, double and thick are the same glyphs.

**Lip Gloss** counts padding and border inside `Width`, margins outside;
`Join*` pads blocks to the tallest or widest; borders have no title either.
**ratatui** has titles on a block's top or bottom border, aligned left,
centre or right, and constraints `Length`, `Percentage`, `Ratio`, `Min`,
`Max`, `Fill` with `Flex` start, end, center, space-between, space-around,
space-evenly.

*Copied*: Ink's prop set and defaults, its border glyphs, ratatui's border
titles. *Different*: no Yoga; one pass per container: fixed and percent
sizes first, then content sizes, then the rest shared by `grow`, or taken
back by `shrink` in proportion, as flexbox does without `min-content`.
Width is measured by bend-tty's `Ansi.width`, so a cell holds a grapheme
cluster and a wide one takes two cells.

## Components

| component | source | what is copied |
| --- | --- | --- |
| Spinner | cli-spinners `dots`: `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` at 80 ms; clack: `◒◐◓◑` magenta at 80 ms | both sets, frame = tick count mod frames, the program's clock |
| Progress | Bubbles: `fw = round((width - percentWidth) * p)`, ` %3.0f%%`; ratatui Gauge, eighth blocks | `█`/`░` bar, a right-aligned percentage, an ETA string the program supplies |
| Select | ink-select-input: blue `❯`, blue label, j/k and arrows wrap, Enter, digits 1-9; clack: `●`/`○` radios, `◻`/`◼` checkboxes, `k j h l` aliases | clack's look and ink's keys but the digits; every item is shown, with no window (not built) |
| Confirm | clack: `● Yes / ○ No`, `y`/`n` submit at once | as is |
| TextInput | ink-text-input and Bubbles draw an inverse cell; Bubbles can place the real cursor; clack draws `█` at the end, placeholder dim with its first character inverse | the **real** cursor, moved there after the frame is drawn; clack's placeholder; Home/End and Delete, which ink-text-input lacks |
| Task list | listr2: yellow spinner running, green `✔` done, red `✖` failed (the message replaces the title), yellow `↓` skipped, dim `◼` waiting; 2 spaces per level; a finished parent collapses its subtasks unless one failed; `› output` under a task | all of it; `✓`/`✗` as the prompt asks |
| Submitted prompt | clack: `◇ message` then `│  dim value`, the rail `┌ │ └` chaining prompts | as is |
| Note | clack: `◇  title ───╮`, body, `├───╯` | as is, on bend-tui's Border |
| Table | lipgloss/table: normal border, a header separator, a style per cell | the shape |
| Link | OSC 8, with bend-tty's `Tty.link` fallback `text (url)` | as is |
| Log lines | Vercel CLI: gray `> text`, yellow `! text`, red `Error:`, `✓ Ready in 47s` with a dim duration, cyan URLs | the colours and the duration style |

`◒◐◓◑` in the target output of the prompt is clack's spinner; cli-spinners'
nearest, `circleHalves`, runs `◐◓◑◒` at 50 ms.

## Loops

**Bubble Tea**: Model, Update, View; a message per event; components carry
an id so a tick reaches only its own spinner. **Ink**: React state and
effects; work runs in promises and sets state. **clack**: each prompt is an
awaited call that leaves a one-line summary.

*Copied*: Bubble Tea's shape, which is `Tui.run`'s already: a state, a
view, an update by events. The work a CLI does runs as its own computation
(`IO.fork`) and posts messages on a `Chan`; the loop folds them in. clack's
one-call prompts are built on that loop.
