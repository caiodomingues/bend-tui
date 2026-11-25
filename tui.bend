# bend-tui: terminal interfaces for Bend 2, on bend-tty. A View is a
# tree of widgets; render lays it out into a Frame, exactly h rows of
# w cells whatever the view (LAWS.bend proves it); Frame.diff writes
# only the rows that changed; Tui.run, in run.bend, is the loop, in the
# shape of Base's App.run: a state, a view of it, an update by the keys
# read. This file runs no effect, so the proofs can import it.
#
#   bend tui.bend        # checks; main renders a small tree as text
#
# A cell is one column: a grapheme cluster (bend-tty's X.Ansi.units)
# that is two columns wide takes two cells, the cluster and a Cell.Pad.

import Base
import ../bend-tty/tty.bend as T
import ../bend-tty/color.bend as C
import ../bend-tty/text.bend as X

# Looks
# -----
# A cell's look is bend-tty's Style and an OSC 8 link ("" for none). It
# is painted at the stream's colour level when a frame becomes a
# string, so a view never knows whether it goes to a pipe.

type Look is Data:
  Look.Of{st: C.Style, link: String}

def Look.plain() -> Look:
  Look.Of{C.Style.plain(), ""}

def Look.st(st: C.Style) -> Look:
  Look.Of{st, ""}

# The 256-colour helpers of the first API, now bend-tty Styles

def Style.plain() -> C.Style:
  C.Style.plain()

def Style.fg(c: U32) -> C.Style:
  C.Style.fg(C.Color.Ansi256{c}, C.Style.plain())

def Style.bold(c: U32) -> C.Style:
  C.Style.bold(Style.fg(c))

def Style.inverse() -> C.Style:
  C.Style.inverse(C.Style.plain())

# Equality, compared field by field so that its reflexivity is a
# structural proof (PROOF.bend)

def Str.same(a: String, b: String) -> Bool:
  match a b:
    case SNil{} SNil{}:
      True{}
    case SCon{Chr{x}, xt} SCon{Chr{y}, yt}:
      Bool.and(U32.is_eq(x, y), Str.same(xt, yt))
    case other1 other2:
      False{}

def Bool.same(a: Bool, b: Bool) -> Bool:
  Cmp.is_eq(Bool.cmp(a, b))

def Color.same(a: C.Color, b: C.Color) -> Bool:
  match a b:
    case C.Color.Default{} C.Color.Default{}:
      True{}
    case C.Color.Basic{x} C.Color.Basic{y}:
      U32.is_eq(x, y)
    case C.Color.Ansi256{x} C.Color.Ansi256{y}:
      U32.is_eq(x, y)
    case C.Color.Rgb{r1, g1, b1} C.Color.Rgb{r2, g2, b2}:
      Bool.and(U32.is_eq(r1, r2), Bool.and(U32.is_eq(g1, g2), U32.is_eq(b1, b2)))
    case other1 other2:
      False{}

def Style.same(a: C.Style, b: C.Style) -> Bool:
  match a b:
    case C.Style{f1, b1, x1, y1, z1, u1, v1, h1, s1} C.Style{f2, b2, x2, y2, z2, u2, v2, h2, s2}:
      Bool.and(Color.same(f1, f2), Bool.and(Color.same(b1, b2),
        Bool.and(Bool.same(x1, x2), Bool.and(Bool.same(y1, y2), Bool.and(Bool.same(z1, z2),
          Bool.and(Bool.same(u1, u2), Bool.and(Bool.same(v1, v2), Bool.and(Bool.same(h1, h2), Bool.same(s1, s2)))))))))

def Look.is_eq(a: Look, b: Look) -> Bool:
  match a b:
    case Look.Of{s1, l1} Look.Of{s2, l2}:
      Bool.and(Style.same(s1, s2), Str.same(l1, l2))

# Cells
# -----

type Cell is Data:
  Cell.Of{g: String, look: Look}   # a cluster
  Cell.Pad{}                       # the second column of a wide cluster: writes nothing

def Cell.blank() -> Cell:
  Cell.Of{" ", Look.plain()}

def Cell.is_eq(a: Cell, b: Cell) -> Bool:
  match a b:
    case Cell.Of{g1, k1} Cell.Of{g2, k2}:
      Bool.and(Str.same(g1, g2), Look.is_eq(k1, k2))
    case Cell.Pad{} Cell.Pad{}:
      True{}
    case other1 other2:
      False{}

# a code point a cell may hold: a control character (below 32, or 127
# to 159) would move the cursor or start an escape, so it becomes a
# blank
def Cell.code(+c: U32) -> U32:
  Bool.pick(U32, Bool.or(U32.is_lt(c, 32), Bool.and(U32.is_ge(c, 127), U32.is_lt(c, 160))), 32, c)

def Cell.safe(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{c}, t}:
      SCon{Chr{Cell.code(c)}, Cell.safe(t)}

# a cluster's cells: none when it takes no column, two when it takes two
def Cell.unit(+lk: Look, u: X.Un, +rest: List<&2, Cell>) -> List<&2, Cell>:
  match u:
    case X.Un.Esc{s}:
      rest
    case X.Un.Cl{g, +w}:
      Bool.pick(List<&2, Cell>, U32.is_eq(w, 0), rest,
        Cell.Of{g, lk} <> Bool.pick(List<&2, Cell>, U32.is_eq(w, 2), Cell.Pad{} <> rest, rest))

def Cell.units(+lk: Look, us: List<&2, X.Un>) -> List<&2, Cell>:
  match us:
    case Nil{}:
      Nil{}
    case u <> t:
      Cell.unit(lk, u, Cell.units(lk, t))

# a string's clusters as cells of one look
def Cell.look(+lk: Look, s: String) -> List<&2, Cell>:
  Cell.units(lk, X.Ansi.units(Cell.safe(s)))

def Cell.text(+st: C.Style, s: String) -> List<&2, Cell>:
  Cell.look(Look.st(st), s)

# Fit
# ---
# fit cuts or pads a row to exactly w cells, and fit_rows a list of
# rows to exactly h rows of w cells, each by recursion on the size
# alone, so the count is structural: the laws fit_len and fit_rows_len
# are one induction each, and every widget's frame goes through them.

def Cell.is_pad(c: Cell) -> Bool:
  match c:
    case Cell.Pad{}:
      True{}
    case Cell.Of{g, k}:
      False{}

def Cell.wide(cs: List<&2, Cell>) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case c <> t:
      Cell.is_pad(c)

# the cell kept in the last column: a wide cluster whose second column
# is cut off would print past the row, so it becomes a blank
def Cell.edge(+last: Bool, c: Cell, cut: Bool) -> Cell:
  Bool.pick(Cell, Bool.and(last, cut), Cell.blank(), c)

def Nat.is_zero(n: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      False{}

def fit(+w: Nat, cs: List<&2, Cell>) -> List<&2, Cell>:
  match w:
    case 0n:
      Nil{}
    case 1n+p:
      match cs:
        case Nil{}:
          Cell.blank() <> fit(p, Nil{})
        case c <> +t:
          Cell.edge(Nat.is_zero(p), c, Cell.wide(t)) <> fit(p, t)

def fit_rows(h: Nat, +w: Nat, rows: List<&2, List<&2, Cell>>) -> List<&2, List<&2, Cell>>:
  match h:
    case 0n:
      Nil{}
    case 1n+p:
      match rows:
        case Nil{}:
          fit(w, Nil{}) <> fit_rows(p, w, Nil{})
        case r <> t:
          fit(w, r) <> fit_rows(p, w, t)

# Views
# -----

type View is Data:
  View.Text{st: C.Style, s: String}             # one row
  Lines{st: C.Style, ls: List<&2, String>}      # a row per string
  Fill{c: Cell}                                 # the whole area
  Above{top: View, bottom: View, rows: Nat}     # top gets rows rows, bottom the rest
  Below{top: View, bottom: View, rows: Nat}     # bottom gets rows rows, top the rest
  Beside{left: View, right: View, cols: Nat}    # left gets cols columns, right the rest
  After{left: View, right: View, cols: Nat}     # right gets cols columns, left the rest
  Split{left: View, right: View, num: Nat, den: Nat}   # left gets w * num / den columns
  Stack{top: View, bottom: View, num: Nat, den: Nat}   # top gets h * num / den rows
  Boxed{title: String, child: View}             # a border with a title; the child inside
  Menu{items: List<&2, String>, sel: Nat}     # a list; item sel highlighted, scrolled into view
  Input{text: String, cursor: Nat}              # one row of text with the cursor cell inverse
  Progress{done: Nat, total: Nat, st: C.Style}  # one row, filled to done / total
  View.Txt{spans: List<&2, Span>, wrap: Wrap}   # styled text, wrapped or cut to the width
  Row{kids: List<&2, Flex>, gap: Nat, justify: Justify, align: Align}   # flex, left to right
  Col{kids: List<&2, Flex>, gap: Nat, justify: Justify, align: Align}   # flex, top to bottom
  Pad{t: Nat, r: Nat, b: Nat, l: Nat, child: View}                      # blank rows and columns around
  Border{line: Line, st: C.Style, title: List<&2, Span>, child: View}   # a border, its title on the top edge
  Sized{w: Size, h: Size, child: View}                                  # a width or height of its own

# Chalk-like text: a span's style applies to what it holds, an inner
# style's set parts win and its unset ones inherit
type Span is Data:
  Span.S{s: String}
  Span.In{st: C.Style, kids: List<&2, Span>}
  Span.Link{url: String, kids: List<&2, Span>}

type Wrap is Data:
  Wrap.Word{}              # wrap-ansi, words to the next row, a longer one alone
  Wrap.Hard{}              # wrap-ansi with hard: a longer word is cut
  Wrap.Cut{at: X.Cut}      # cli-truncate: one row, an ellipsis at End, Start or Middle

type Size is Data:
  Size.Auto{}              # the content's size
  Size.Cols{n: Nat}        # fixed: columns, or rows on the vertical axis
  Size.Pct{p: Nat}         # percent of the parent

# where free space goes on the main axis, as CSS justify-content
type Justify is Data:
  Justify.Start{}
  Justify.End{}
  Justify.Center{}
  Justify.Between{}
  Justify.Around{}
  Justify.Evenly{}

# where a child sits on the cross axis, as CSS align-items
type Align is Data:
  Align.Start{}
  Align.End{}
  Align.Center{}
  Align.Stretch{}

# border glyphs, as cli-boxes
type Line is Data:
  Line.Single{}
  Line.Round{}
  Line.Double{}
  Line.Bold{}

# a child of a Row or Col: Ink's defaults are Flex{v, 0n, 1n, Size.Auto{}}
type Flex is Data:
  Flex{v: View, grow: Nat, shrink: Nat, basis: Size}

# rows placed side by side: each left row followed by its right row
def hcat(ls: List<&2, List<&2, Cell>>, rs: List<&2, List<&2, Cell>>) -> List<&2, List<&2, Cell>>:
  match ls rs:
    case Nil{} r:
      Nil{}
    case l <> lt Nil{}:
      Nil{}
    case l <> lt r <> rt:
      List.append(&2, Cell, l, r) <> hcat(lt, rt)

def lines(+st: C.Style, ls: List<&2, String>) -> List<&2, List<&2, Cell>>:
  match ls:
    case Nil{}:
      Nil{}
    case s <> t:
      Cell.text(st, s) <> lines(st, t)

# the first item shown, so that sel is on screen: the last row when
# it is past the h rows
def menu_top(+sel: Nat, +h: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(sel, h), 0n, 1n+Nat.sub(sel, h))

# the menu's rows from item i on: the selected one inverse
def menu_rows(items: List<&2, String>, +i: Nat, +sel: Nat) -> List<&2, List<&2, Cell>>:
  match items:
    case Nil{}:
      Nil{}
    case s <> t:
      Cell.text(Bool.pick(C.Style, Nat.is_eq(i, sel), Style.inverse(), Style.plain()), s) <> menu_rows(t, 1n+i, sel)

def Cell.invert(c: Cell) -> Cell:
  match c:
    case Cell.Of{g, k}:
      Cell.Of{g, Look.st(Style.inverse())}
    case Cell.Pad{}:
      Cell.Pad{}

# the input's cells: the text, with the cluster at the cursor inverse;
# a blank one when the cursor is at or past the end
def input_cells(cs: List<&2, Cell>, +cursor: Nat) -> List<&2, Cell>:
  match cs cursor:
    case Nil{} n:
      [Cell.Of{" ", Look.st(Style.inverse())}]
    case c <> t 0n:
      Cell.invert(c) <> t
    case c <> t 1n+p:
      c <> input_cells(t, p)

# n cells of the code point ch in st
def cells_of(n: Nat, +ch: U32, +st: C.Style) -> List<&2, Cell>:
  List.replicate(Cell, n, Cell.Of{SCon{Chr{ch}, SNil{}}, Look.st(st)})

# the filled part of a bar: w * done / total cells, total at least 1
def bar_cells(+w: Nat, +done: Nat, +total: Nat, +st: C.Style) -> List<&2, Cell>:
  +n = Nat.div(Nat.mul(w, Nat.min(done, total)), Nat.max(total, 1n))
  List.append(&2, Cell, cells_of(n, 9608, st), cells_of(Nat.sub(w, n), 9617, st))

# a box: a top row with the title, the child's rows between bars, a
# bottom row. Box-drawing code points: 9484 9472 9488 9474 9492 9496
def box_top(+w: Nat, title: String) -> List<&2, Cell>:
  fit(w, List.append(&2, Cell, cells_of(1n, 9484, Style.plain()), List.append(&2, Cell, Cell.text(Style.plain(), title), cells_of(w, 9472, Style.plain()))))

def box_bottom(+w: Nat) -> List<&2, Cell>:
  fit(w, List.append(&2, Cell, cells_of(1n, 9492, Style.plain()), cells_of(w, 9472, Style.plain())))

def box_side(rows: List<&2, List<&2, Cell>>) -> List<&2, List<&2, Cell>>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      List.append(&2, Cell, List.append(&2, Cell, cells_of(1n, 9474, Style.plain()), r), cells_of(1n, 9474, Style.plain())) <> box_side(t)

# the box's corners on a top or bottom row: the last cell replaced
def box_corner(+w: Nat, row: List<&2, Cell>, +corner: U32) -> List<&2, Cell>:
  List.append(&2, Cell, fit(Nat.sub(w, 1n), row), cells_of(1n, corner, Style.plain()))

def Cell.str(c: Cell) -> String:
  match c:
    case Cell.Of{g, k}:
      g
    case Cell.Pad{}:
      ""

def Cell.look_of(c: Cell, +dflt: Look) -> Look:
  match c:
    case Cell.Of{g, k}:
      k
    case Cell.Pad{}:
      dflt

# Text
# ----
# Spans become cells, a look each, one list per hard line. Wrapping and
# truncation are bend-tty's, on the line's plain text; the looks are
# then laid back on by walking the result beside the cells it came
# from: the result is the text less the spaces wrap drops at a break,
# plus line breaks and the ellipsis, so one pass places every cluster.

def Color.over(outer: C.Color, inner: C.Color) -> C.Color:
  match inner:
    case C.Color.Default{}:
      outer
    case other:
      other

def Style.over(a: C.Style, b: C.Style) -> C.Style:
  match a b:
    case C.Style{f1, b1, x1, y1, z1, u1, v1, h1, s1} C.Style{f2, b2, x2, y2, z2, u2, v2, h2, s2}:
      C.Style{Color.over(f1, f2), Color.over(b1, b2), Bool.or(x1, x2), Bool.or(y1, y2), Bool.or(z1, z2),
        Bool.or(u1, u2), Bool.or(v1, v2), Bool.or(h1, h2), Bool.or(s1, s2)}

def Look.over(k: Look, st: C.Style) -> Look:
  match k:
    case Look.Of{s, l}:
      Look.Of{Style.over(s, st), l}

def Look.linked(k: Look, url: String) -> Look:
  match k:
    case Look.Of{s, l}:
      Look.Of{s, url}

def Str.split.cur(nl: Bool, +c: U32, cur: String) -> String:
  match nl:
    case True{}:
      SNil{}
    case False{}:
      SCon{Chr{c}, cur}

def Str.split.out(nl: Bool, +cur: String, out: List<&2, String>) -> List<&2, String>:
  match nl:
    case True{}:
      String.reverse(cur) <> out
    case False{}:
      out

# the pieces between line breaks, last first; cur is the piece in
# progress, reversed
def Str.split.go(s: String, +cur: String, out: List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}:
      String.reverse(cur) <> out
    case SCon{Chr{+c}, t}:
      +nl = U32.is_eq(c, 10)
      Str.split.go(t, Str.split.cur(nl, c, cur), Str.split.out(nl, cur, out))

def Str.lines(s: String) -> List<&2, String>:
  List.reverse(&2, String, Str.split.go(s, "", Nil{}))

type Tok is Data:
  Tok.C{c: Cell}
  Tok.Nl{}

def Tok.cells(cs: List<&2, Cell>) -> List<&2, Tok>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      Tok.C{c} <> Tok.cells(t)

def Tok.nl(first: Bool) -> List<&2, Tok>:
  match first:
    case True{}:
      Nil{}
    case False{}:
      [Tok.Nl{}]

def Tok.segs(segs: List<&2, String>, +lk: Look, first: Bool) -> List<&2, Tok>:
  match segs:
    case Nil{}:
      Nil{}
    case s <> t:
      List.append(&2, Tok, Tok.nl(first), List.append(&2, Tok, Tok.cells(Cell.look(lk, s)), Tok.segs(t, lk, False{})))

def Span.toks(sp: List<&2, Span>, +lk: Look) -> List<&2, Tok>:
  match sp:
    case Nil{}:
      Nil{}
    case Span.S{s} <> t:
      List.append(&2, Tok, Tok.segs(Str.lines(s), lk, True{}), Span.toks(t, lk))
    case Span.In{st, kids} <> t:
      List.append(&2, Tok, Span.toks(kids, Look.over(lk, st)), Span.toks(t, lk))
    case Span.Link{url, kids} <> t:
      List.append(&2, Tok, Span.toks(kids, Look.linked(lk, url)), Span.toks(t, lk))

# the hard lines, last first; cur is the line in progress, reversed
def Tok.lines(ts: List<&2, Tok>, cur: List<&2, Cell>, out: List<&2, List<&2, Cell>>) -> List<&2, List<&2, Cell>>:
  match ts:
    case Nil{}:
      List.reverse(&2, Cell, cur) <> out
    case Tok.C{c} <> t:
      Tok.lines(t, c <> cur, out)
    case Tok.Nl{} <> t:
      Tok.lines(t, Nil{}, List.reverse(&2, Cell, cur) <> out)

def Txt.lines(sp: List<&2, Span>) -> List<&2, List<&2, Cell>>:
  List.reverse(&2, List<&2, Cell>, Tok.lines(Span.toks(sp, Look.plain()), Nil{}, Nil{}))

def Cells.plain(cs: List<&2, Cell>) -> String:
  match cs:
    case Nil{}:
      ""
    case c <> t:
      Cell.str(c) ++ Cells.plain(t)

def Cells.widest(ls: List<&2, List<&2, Cell>>) -> Nat:
  match ls:
    case Nil{}:
      0n
    case l <> t:
      Nat.max(List.length(&2, Cell, l), Cells.widest(t))

# The alignment: the result's units left to place, the cells they came
# from, the row in progress (reversed), the rows done (reversed)
type Al is Data:
  Al{out: List<&2, X.Un>, orig: List<&2, Cell>, cur: List<&2, Cell>, rows: List<&2, List<&2, Cell>>}

def Al.emit(+g: String, +w: U32, +lk: Look, +cur: List<&2, Cell>) -> List<&2, Cell>:
  Bool.pick(List<&2, Cell>, U32.is_eq(w, 0), cur,
    Bool.pick(List<&2, Cell>, U32.is_eq(w, 2), Cell.Pad{} <> Cell.Of{g, lk} <> cur, Cell.Of{g, lk} <> cur))

# a cluster of the result against the next cell: the same cluster is
# placed with the cell's look; a space the result lacks was dropped at
# a break; anything else (the ellipsis) was put in, with the look of
# the cell it stands before
def Al.of(same: Bool, space: Bool, +g: String, +w: U32, ot: List<&2, X.Un>, +g0: String, +k: Look, t: List<&2, Cell>,
          cur: List<&2, Cell>, rows: List<&2, List<&2, Cell>>) -> Al:
  match same space:
    case True{} sp:
      Al{ot, t, Al.emit(g, w, k, cur), rows}
    case False{} True{}:
      Al{X.Un.Cl{g, w} <> ot, t, cur, rows}
    case False{} False{}:
      Al{ot, Cell.Of{g0, k} <> t, Al.emit(g, w, k, cur), rows}

def Al.place(+g: String, +w: U32, ot: List<&2, X.Un>, orig: List<&2, Cell>, cur: List<&2, Cell>, rows: List<&2, List<&2, Cell>>) -> Al:
  match orig:
    case Nil{}:
      Al{ot, Nil{}, Al.emit(g, w, Look.plain(), cur), rows}
    case Cell.Pad{} <> t:
      Al{X.Un.Cl{g, w} <> ot, t, cur, rows}
    case Cell.Of{+g0, k} <> t:
      Al.of(Str.same(g, g0), Str.same(g0, " "), g, w, ot, g0, k, t, cur, rows)

def Al.cl(nl: Bool, +g: String, +w: U32, ot: List<&2, X.Un>, orig: List<&2, Cell>, cur: List<&2, Cell>, rows: List<&2, List<&2, Cell>>) -> Al:
  match nl:
    case True{}:
      Al{ot, orig, Nil{}, List.reverse(&2, Cell, cur) <> rows}
    case False{}:
      Al.place(g, w, ot, orig, cur, rows)

def Al.step(st: Al) -> Al:
  match st:
    case Al{out, orig, cur, rows}:
      match out:
        case Nil{}:
          Al{Nil{}, orig, cur, rows}
        case X.Un.Esc{s} <> ot:
          Al{ot, orig, cur, rows}
        case X.Un.Cl{+g, w} <> ot:
          Al.cl(Str.same(g, "\n"), g, w, ot, orig, cur, rows)

# each step places a unit or drops a cell, so the two lengths bound it
def Al.run(fuel: Nat, st: Al) -> Al:
  match fuel:
    case 0n:
      st
    case 1n+f:
      Al.run(f, Al.step(st))

def Al.rows(st: Al) -> List<&2, List<&2, Cell>>:
  match st:
    case Al{out, orig, cur, rows}:
      List.reverse(&2, List<&2, Cell>, List.reverse(&2, Cell, cur) <> rows)

def Al.align(+out: List<&2, X.Un>, +orig: List<&2, Cell>) -> List<&2, List<&2, Cell>>:
  Al.rows(Al.run(1n+Nat.add(List.length(&2, X.Un, out), List.length(&2, Cell, orig)), Al{out, orig, Nil{}, Nil{}}))

def Un.is_ell(u: X.Un) -> Bool:
  match u:
    case X.Un.Cl{g, w}:
      Str.same(g, "…")
    case X.Un.Esc{s}:
      False{}

def Un.pre(us: List<&2, X.Un>) -> List<&2, X.Un>:
  match us:
    case Nil{}:
      Nil{}
    case +u <> t:
      Bool.pick(List<&2, X.Un>, Un.is_ell(u), Nil{}, u <> Un.pre(t))

def Un.post(us: List<&2, X.Un>) -> List<&2, X.Un>:
  match us:
    case Nil{}:
      Nil{}
    case +u <> +t:
      Bool.pick(List<&2, X.Un>, Un.is_ell(u), t, Un.post(t))

def Un.has_ell(us: List<&2, X.Un>) -> Bool:
  match us:
    case Nil{}:
      False{}
    case u <> t:
      Bool.or(Un.is_ell(u), Un.has_ell(t))

def Cells.unpad(cs: List<&2, Cell>) -> List<&2, Cell>:
  match cs:
    case Nil{}:
      Nil{}
    case Cell.Pad{} <> t:
      Cells.unpad(t)
    case c <> t:
      c <> Cells.unpad(t)

def Cell.repad(c: Cell, +rest: List<&2, Cell>) -> List<&2, Cell>:
  match c:
    case Cell.Of{+g, k}:
      Cell.Of{g, k} <> Bool.pick(List<&2, Cell>, U32.is_eq(X.Ansi.width(g), 2), Cell.Pad{} <> rest, rest)
    case Cell.Pad{}:
      rest

def Cells.repad(cs: List<&2, Cell>) -> List<&2, Cell>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      Cell.repad(c, Cells.repad(t))

def Cells.first(cs: List<&2, List<&2, Cell>>) -> List<&2, Cell>:
  match cs:
    case Nil{}:
      Nil{}
    case r <> t:
      r

def Cells.last_look(cs: List<&2, Cell>, +dflt: Look) -> Look:
  match cs:
    case Nil{}:
      dflt
    case c <> t:
      Cells.last_look(t, Cell.look_of(c, dflt))

# a truncated line: the part before the ellipsis placed from the front,
# the part after it from the back
def Txt.cut.ell(+us: List<&2, X.Un>, +line: List<&2, Cell>) -> List<&2, Cell>:
  +pre = Cells.first(Al.align(Un.pre(us), line))
  +post = Cells.repad(List.reverse(&2, Cell, Cells.unpad(Cells.first(Al.align(List.reverse(&2, X.Un, Un.post(us)), List.reverse(&2, Cell, line))))))
  List.append(&2, Cell, pre, Cell.Of{"…", Cells.last_look(pre, Cells.last_look(List.take(&2, Cell, post, 1n), Look.plain()))} <> post)

def Txt.cut.if(+us: List<&2, X.Un>, +line: List<&2, Cell>, ell: Bool) -> List<&2, List<&2, Cell>>:
  match ell:
    case True{}:
      [Txt.cut.ell(us, line)]
    case False{}:
      Al.align(us, line)

def Txt.cut(+line: List<&2, Cell>, +us: List<&2, X.Un>) -> List<&2, List<&2, Cell>>:
  Txt.cut.if(us, line, Un.has_ell(us))

def Txt.wrap(+line: List<&2, Cell>, wrap: Wrap, +w: Nat) -> List<&2, List<&2, Cell>>:
  match wrap:
    case Wrap.Word{}:
      Al.align(X.Ansi.units(X.Ansi.wrap(Cells.plain(line), U32.from_nat(w), False{})), line)
    case Wrap.Hard{}:
      Al.align(X.Ansi.units(X.Ansi.wrap(Cells.plain(line), U32.from_nat(w), True{})), line)
    case Wrap.Cut{at}:
      Txt.cut(line, X.Ansi.units(X.Ansi.truncate(Cells.plain(line), U32.from_nat(w), at)))

def Txt.wrap.all(ls: List<&2, List<&2, Cell>>, +wrap: Wrap, +w: Nat) -> List<&2, List<&2, Cell>>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      List.append(&2, List<&2, Cell>, Txt.wrap(l, wrap, w), Txt.wrap.all(t, wrap, w))

# a text's rows at width w
def Txt.rows(sp: List<&2, Span>, +wrap: Wrap, +w: Nat) -> List<&2, List<&2, Cell>>:
  Txt.wrap.all(Txt.lines(sp), wrap, w)

# Measures
# --------
# View.width is a view's natural width, its widest row unwrapped;
# View.height the rows it takes at a width when nothing bounds it, the
# height of an inline frame.

def Lines.widest(+st: C.Style, ls: List<&2, String>) -> Nat:
  match ls:
    case Nil{}:
      0n
    case s <> t:
      Nat.max(List.length(&2, Cell, Cell.text(st, s)), Lines.widest(st, t))

def Size.nat(b: Size, +nat: Nat) -> Nat:
  match b:
    case Size.Cols{n}:
      n
    case other:
      nat

def Size.of(b: Size, +nat: Nat, +whole: Nat) -> Nat:
  match b:
    case Size.Auto{}:
      nat
    case Size.Cols{n}:
      n
    case Size.Pct{p}:
      Nat.div(Nat.mul(whole, p), 100n)

def Lay.gapif(rest: List<&2, Flex>, +g: Nat) -> Nat:
  match rest:
    case Nil{}:
      0n
    case f <> t:
      g

def View.width(+v: View) -> Nat:
  match v:
    case View.Text{st, s}:
      List.length(&2, Cell, Cell.text(st, s))
    case Lines{st, ls}:
      Lines.widest(st, ls)
    case Fill{c}:
      0n
    case Above{top, bottom, rows}:
      Nat.max(View.width(top), View.width(bottom))
    case Below{top, bottom, rows}:
      Nat.max(View.width(top), View.width(bottom))
    case Beside{left, right, cols}:
      Nat.add(cols, View.width(right))
    case After{left, right, cols}:
      Nat.add(View.width(left), cols)
    case Split{left, right, num, den}:
      Nat.add(View.width(left), View.width(right))
    case Stack{top, bottom, num, den}:
      Nat.max(View.width(top), View.width(bottom))
    case Boxed{title, child}:
      2n+Nat.max(View.width(child), List.length(&2, Cell, Cell.text(Style.plain(), title)))
    case Menu{items, sel}:
      Lines.widest(Style.plain(), items)
    case Input{text, cursor}:
      1n+List.length(&2, Cell, Cell.text(Style.plain(), text))
    case Progress{done, total, st}:
      0n
    case View.Txt{spans, wrap}:
      Cells.widest(Txt.lines(spans))
    case Row{kids, gap, justify, align}:
      match kids:
        case Nil{}:
          0n
        case Flex{fv, g, s, b} <> rest:
          Nat.add(Size.nat(b, View.width(fv)), Nat.add(Lay.gapif(rest, gap), View.width(Row{rest, gap, justify, align})))
    case Col{kids, gap, justify, align}:
      match kids:
        case Nil{}:
          0n
        case Flex{fv, g, s, b} <> rest:
          Nat.max(View.width(fv), View.width(Col{rest, gap, justify, align}))
    case Pad{t, r, b, l, child}:
      Nat.add(Nat.add(l, r), View.width(child))
    case Border{line, st, title, child}:
      2n+Nat.max(View.width(child), 4n+Cells.widest(Txt.lines(title)))
    case Sized{sw, sh, child}:
      Size.nat(sw, View.width(child))

# The flex arithmetic. A container's children, in order: the sum of
# their bases, of their grow factors, of shrink times basis (flexbox
# shrinks in proportion to both), and their count.
type Sums is Data:
  Sums{b: Nat, g: Nat, s: Nat, n: Nat}

def Sums.add(+bb: Nat, +g: Nat, +s: Nat, r: Sums) -> Sums:
  match r:
    case Sums{b, gg, ss, n}:
      Sums{Nat.add(bb, b), Nat.add(g, gg), Nat.add(Nat.mul(s, bb), ss), 1n+n}

# the main size of the first child: its basis, plus its share of the
# free space by grow, or less its share of the overflow by shrink
def Lay.first(+bb: Nat, +g: Nat, +s: Nat, su: Sums, +gap: Nat, +w: Nat) -> Nat:
  match su:
    case Sums{b, gg, ss, n}:
      +tot = Nat.add(b, Nat.mul(gap, Nat.sub(n, 1n)))
      Bool.pick(Nat, Nat.is_le(tot, w),
        Nat.add(bb, Nat.div(Nat.mul(Nat.sub(w, tot), g), Nat.max(gg, 1n))),
        Nat.sub(bb, Nat.div(Nat.mul(Nat.sub(tot, w), Nat.mul(s, bb)), Nat.max(ss, 1n))))

# the space justify places: what is left when no child grows
def Lay.free(su: Sums, +gap: Nat, +w: Nat) -> Nat:
  match su:
    case Sums{b, gg, ss, n}:
      Bool.pick(Nat, Nat.is_zero(gg), Nat.sub(w, Nat.add(b, Nat.mul(gap, Nat.sub(n, 1n)))), 0n)

def Lay.count(su: Sums) -> Nat:
  match su:
    case Sums{b, g, s, n}:
      n

def Lay.lead(j: Justify, +free: Nat, +n: Nat) -> Nat:
  match j:
    case Justify.Start{}:
      0n
    case Justify.End{}:
      free
    case Justify.Center{}:
      Nat.div(free, 2n)
    case Justify.Between{}:
      0n
    case Justify.Around{}:
      Nat.div(free, Nat.max(Nat.mul(2n, n), 1n))
    case Justify.Evenly{}:
      Nat.div(free, 1n+n)

def Lay.between(j: Justify, +free: Nat, +n: Nat, +gap: Nat) -> Nat:
  match j:
    case Justify.Between{}:
      Nat.add(gap, Nat.div(free, Nat.max(Nat.sub(n, 1n), 1n)))
    case Justify.Around{}:
      Nat.add(gap, Nat.div(free, Nat.max(n, 1n)))
    case Justify.Evenly{}:
      Nat.add(gap, Nat.div(free, 1n+n))
    case other:
      gap

def Lay.row_sums(kids: List<&2, Flex>, +w: Nat) -> Sums:
  match kids:
    case Nil{}:
      Sums{0n, 0n, 0n, 0n}
    case Flex{v, g, s, b} <> t:
      Sums.add(Size.of(b, View.width(v), w), g, s, Lay.row_sums(t, w))

def Lay.row_first(+kids: List<&2, Flex>, +w: Nat, +gap: Nat) -> Nat:
  match kids:
    case Nil{}:
      0n
    case Flex{v, g, s, b} <> t:
      Lay.first(Size.of(b, View.width(v), w), g, s, Lay.row_sums(kids, w), gap, w)

def Lay.row_lead(+kids: List<&2, Flex>, +w: Nat, +gap: Nat, j: Justify) -> Nat:
  +su = Lay.row_sums(kids, w)
  Lay.lead(j, Lay.free(su, gap, w), Lay.count(su))

def Lay.row_between(+kids: List<&2, Flex>, +w: Nat, +gap: Nat, j: Justify) -> Nat:
  +su = Lay.row_sums(kids, w)
  Lay.between(j, Lay.free(su, gap, w), Lay.count(su), gap)

# a child's width across a Col: all of it when stretched, else its own
def Lay.cross_w(a: Align, +v: View, +w: Nat) -> Nat:
  match a:
    case Align.Stretch{}:
      w
    case other:
      Nat.min(View.width(v), w)

def Lay.is_stretch(a: Align) -> Bool:
  match a:
    case Align.Stretch{}:
      True{}
    case other:
      False{}

# the rest of a container after its first child is laid out as Start
# with the gap the first one left; the termination check needs the
# rebuilt node to keep its own fields, so this rides beside it
type Cont is Data:
  Cont.No{}
  Cont.Gap{g: Nat}

def Cont.gap(c: Cont, +gap: Nat) -> Nat:
  match c:
    case Cont.No{}:
      gap
    case Cont.Gap{g}:
      g

def Cont.just(c: Cont, j: Justify) -> Justify:
  match c:
    case Cont.No{}:
      j
    case Cont.Gap{g}:
      Justify.Start{}

def View.height.go(+v: View, +w: Nat, +cont: Cont) -> Nat:
  match v:
    case View.Text{st, s}:
      1n
    case Lines{st, ls}:
      List.length(&2, String, ls)
    case Fill{c}:
      1n
    case Above{top, bottom, rows}:
      Nat.add(rows, View.height.go(bottom, w, Cont.No{}))
    case Below{top, bottom, rows}:
      Nat.add(View.height.go(top, w, Cont.No{}), rows)
    case Beside{left, right, cols}:
      Nat.max(View.height.go(left, cols, Cont.No{}), View.height.go(right, Nat.sub(w, cols), Cont.No{}))
    case After{left, right, cols}:
      Nat.max(View.height.go(left, Nat.sub(w, cols), Cont.No{}), View.height.go(right, cols, Cont.No{}))
    case Split{left, right, num, den}:
      +cols = Nat.div(Nat.mul(w, num), Nat.max(den, 1n))
      Nat.max(View.height.go(left, cols, Cont.No{}), View.height.go(right, Nat.sub(w, cols), Cont.No{}))
    case Stack{top, bottom, num, den}:
      Nat.add(View.height.go(top, w, Cont.No{}), View.height.go(bottom, w, Cont.No{}))
    case Boxed{title, child}:
      2n+View.height.go(child, Nat.sub(w, 2n), Cont.No{})
    case Menu{items, sel}:
      List.length(&2, String, items)
    case Input{text, cursor}:
      1n
    case Progress{done, total, st}:
      1n
    case View.Txt{spans, wrap}:
      List.length(&2, List<&2, Cell>, Txt.rows(spans, wrap, w))
    case Row{kids, gap, justify, align}:
      match kids:
        case Nil{}:
          0n
        case Flex{fv, g, s, b} <> rest:
          +ks = {Flex{fv, g, s, b} <> rest : List<&2, Flex>}
          +eg = Cont.gap(cont, gap)
          +ej = Cont.just(cont, justify)
          +lead = Lay.row_lead(ks, w, eg, ej)
          +kw = Lay.row_first(ks, w, eg)
          +btw = Lay.row_between(ks, w, eg, ej)
          Nat.max(View.height.go(fv, kw, Cont.No{}),
            View.height.go(Row{rest, gap, justify, align}, Nat.sub(w, Nat.add(lead, Nat.add(kw, Lay.gapif(rest, btw)))), Cont.Gap{btw}))
    case Col{kids, gap, justify, align}:
      match kids:
        case Nil{}:
          0n
        case Flex{fv, g, s, b} <> rest:
          Nat.add(Size.nat(b, View.height.go(fv, Lay.cross_w(align, fv, w), Cont.No{})),
            Nat.add(Lay.gapif(rest, gap), View.height.go(Col{rest, gap, justify, align}, w, Cont.No{})))
    case Pad{t, r, b, l, child}:
      Nat.add(Nat.add(t, b), View.height.go(child, Nat.sub(w, Nat.add(l, r)), Cont.No{}))
    case Border{line, st, title, child}:
      2n+View.height.go(child, Nat.sub(w, 2n), Cont.No{})
    case Sized{sw, sh, child}:
      Size.nat(sh, View.height.go(child, Nat.min(Size.of(sw, View.width(child), w), w), Cont.No{}))

def View.height(+v: View, +w: Nat) -> Nat:
  View.height.go(v, w, Cont.No{})

def Lay.col_sums(kids: List<&2, Flex>, +w: Nat, +h: Nat, +a: Align) -> Sums:
  match kids:
    case Nil{}:
      Sums{0n, 0n, 0n, 0n}
    case Flex{+v, g, s, b} <> t:
      Sums.add(Size.of(b, View.height(v, Lay.cross_w(a, v, w)), h), g, s, Lay.col_sums(t, w, h, a))

def Lay.col_first(+kids: List<&2, Flex>, +w: Nat, +h: Nat, +gap: Nat, +a: Align) -> Nat:
  match kids:
    case Nil{}:
      0n
    case Flex{v, g, s, b} <> t:
      Lay.first(Size.of(b, View.height(v, Lay.cross_w(a, v, w)), h), g, s, Lay.col_sums(kids, w, h, a), gap, h)

def Lay.col_lead(+kids: List<&2, Flex>, +w: Nat, +h: Nat, +gap: Nat, j: Justify, +a: Align) -> Nat:
  +su = Lay.col_sums(kids, w, h, a)
  Lay.lead(j, Lay.free(su, gap, h), Lay.count(su))

def Lay.col_between(+kids: List<&2, Flex>, +w: Nat, +h: Nat, +gap: Nat, j: Justify, +a: Align) -> Nat:
  +su = Lay.col_sums(kids, w, h, a)
  Lay.between(j, Lay.free(su, gap, h), Lay.count(su), gap)

def blank_rows(n: Nat, +w: Nat) -> List<&2, List<&2, Cell>>:
  List.replicate(List<&2, Cell>, n, List.replicate(Cell, w, Cell.blank()))

def Lay.indent(rows: List<&2, List<&2, Cell>>, +n: Nat) -> List<&2, List<&2, Cell>>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      List.append(&2, Cell, List.replicate(Cell, n, Cell.blank()), r) <> Lay.indent(t, n)

# the offset of a child of size k in a cross size of m
def Lay.offset(a: Align, +k: Nat, +m: Nat) -> Nat:
  match a:
    case Align.End{}:
      Nat.sub(m, k)
    case Align.Center{}:
      Nat.div(Nat.sub(m, k), 2n)
    case other:
      0n

# Borders
# -------

type Glyphs is Data:
  Glyphs{tl: U32, hz: U32, tr: U32, vt: U32, bl: U32, br: U32}

def Line.glyphs(l: Line) -> Glyphs:
  match l:
    case Line.Single{}:
      Glyphs{9484, 9472, 9488, 9474, 9492, 9496}
    case Line.Round{}:
      Glyphs{9581, 9472, 9582, 9474, 9584, 9583}
    case Line.Double{}:
      Glyphs{9556, 9552, 9559, 9553, 9562, 9565}
    case Line.Bold{}:
      Glyphs{9487, 9473, 9491, 9475, 9495, 9499}

def Glyphs.tl(g: Glyphs) -> U32:
  match g:
    case Glyphs{tl, hz, tr, vt, bl, br}:
      tl

def Glyphs.hz(g: Glyphs) -> U32:
  match g:
    case Glyphs{tl, hz, tr, vt, bl, br}:
      hz

def Glyphs.tr(g: Glyphs) -> U32:
  match g:
    case Glyphs{tl, hz, tr, vt, bl, br}:
      tr

def Glyphs.vt(g: Glyphs) -> U32:
  match g:
    case Glyphs{tl, hz, tr, vt, bl, br}:
      vt

def Glyphs.bl(g: Glyphs) -> U32:
  match g:
    case Glyphs{tl, hz, tr, vt, bl, br}:
      bl

def Glyphs.br(g: Glyphs) -> U32:
  match g:
    case Glyphs{tl, hz, tr, vt, bl, br}:
      br

def Border.title(+gl: Glyphs, +st: C.Style, title: List<&2, Span>, +w: Nat) -> List<&2, Cell>:
  match title:
    case Nil{}:
      Nil{}
    case s <> t:
      List.append(&2, Cell, cells_of(1n, Glyphs.hz(gl), st),
        List.append(&2, Cell, cells_of(1n, 32, st),
          List.append(&2, Cell, Cells.first(Txt.rows(s <> t, Wrap.Cut{X.Cut.End{}}, Nat.sub(w, 6n))), cells_of(1n, 32, st))))

def Border.top(+gl: Glyphs, +st: C.Style, title: List<&2, Span>, +w: Nat) -> List<&2, Cell>:
  List.append(&2, Cell, fit(Nat.sub(w, 1n), List.append(&2, Cell, cells_of(1n, Glyphs.tl(gl), st),
    List.append(&2, Cell, Border.title(gl, st, title, w), cells_of(w, Glyphs.hz(gl), st)))), cells_of(1n, Glyphs.tr(gl), st))

def Border.bottom(+gl: Glyphs, +st: C.Style, +w: Nat) -> List<&2, Cell>:
  List.append(&2, Cell, fit(Nat.sub(w, 1n), List.append(&2, Cell, cells_of(1n, Glyphs.bl(gl), st), cells_of(w, Glyphs.hz(gl), st))),
    cells_of(1n, Glyphs.br(gl), st))

def Border.sides(rows: List<&2, List<&2, Cell>>, +gl: Glyphs, +st: C.Style) -> List<&2, List<&2, Cell>>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      List.append(&2, Cell, List.append(&2, Cell, cells_of(1n, Glyphs.vt(gl), st), r), cells_of(1n, Glyphs.vt(gl), st)) <> Border.sides(t, gl, st)

# Render
# ------
# draw is one recursive def over the view, each arm the rows a widget
# wants, with every child rendered through fit_rows; render fits the
# whole, so a frame is h rows of w cells whatever the view, and the
# laws render_rows and render_cols are the fit lemmas applied

def draw.go(+v: View, +w: Nat, +h: Nat, +cont: Cont) -> List<&2, List<&2, Cell>>:
  match v:
    case View.Text{st, s}:
      [Cell.text(st, s)]
    case Lines{st, ls}:
      lines(st, ls)
    case Fill{c}:
      List.replicate(List<&2, Cell>, h, List.replicate(Cell, w, c))
    case Above{top, bottom, rows}:
      List.append(&2, List<&2, Cell>,
        fit_rows(rows, w, draw.go(top, w, rows, Cont.No{})),
        fit_rows(Nat.sub(h, rows), w, draw.go(bottom, w, Nat.sub(h, rows), Cont.No{})))
    case Below{top, bottom, rows}:
      List.append(&2, List<&2, Cell>,
        fit_rows(Nat.sub(h, rows), w, draw.go(top, w, Nat.sub(h, rows), Cont.No{})),
        fit_rows(rows, w, draw.go(bottom, w, rows, Cont.No{})))
    case Beside{left, right, cols}:
      hcat(fit_rows(h, cols, draw.go(left, cols, h, Cont.No{})), fit_rows(h, Nat.sub(w, cols), draw.go(right, Nat.sub(w, cols), h, Cont.No{})))
    case After{left, right, cols}:
      hcat(fit_rows(h, Nat.sub(w, cols), draw.go(left, Nat.sub(w, cols), h, Cont.No{})), fit_rows(h, cols, draw.go(right, cols, h, Cont.No{})))
    case Split{left, right, num, den}:
      +cols = Nat.div(Nat.mul(w, num), Nat.max(den, 1n))
      hcat(fit_rows(h, cols, draw.go(left, cols, h, Cont.No{})), fit_rows(h, Nat.sub(w, cols), draw.go(right, Nat.sub(w, cols), h, Cont.No{})))
    case Stack{top, bottom, num, den}:
      +rows = Nat.div(Nat.mul(h, num), Nat.max(den, 1n))
      List.append(&2, List<&2, Cell>,
        fit_rows(rows, w, draw.go(top, w, rows, Cont.No{})),
        fit_rows(Nat.sub(h, rows), w, draw.go(bottom, w, Nat.sub(h, rows), Cont.No{})))
    case Boxed{title, child}:
      List.append(&2, List<&2, Cell>,
        [box_corner(w, box_top(w, title), 9488)],
        List.append(&2, List<&2, Cell>,
          box_side(fit_rows(Nat.sub(h, 2n), Nat.sub(w, 2n), draw.go(child, Nat.sub(w, 2n), Nat.sub(h, 2n), Cont.No{}))),
          [box_corner(w, box_bottom(w), 9496)]))
    case Menu{items, sel}:
      menu_rows(List.drop(&2, String, items, menu_top(sel, h)), menu_top(sel, h), sel)
    case Input{text, cursor}:
      [input_cells(Cell.text(Style.plain(), text), cursor)]
    case Progress{done, total, st}:
      [bar_cells(w, done, total, st)]
    case View.Txt{spans, wrap}:
      Txt.rows(spans, wrap, w)
    case Row{kids, gap, justify, align}:
      match kids:
        case Nil{}:
          Nil{}
        case Flex{fv, g, s, b} <> rest:
          +ks = {Flex{fv, g, s, b} <> rest : List<&2, Flex>}
          +eg = Cont.gap(cont, gap)
          +ej = Cont.just(cont, justify)
          +lead = Lay.row_lead(ks, w, eg, ej)
          +kw = Lay.row_first(ks, w, eg)
          +btw = Lay.row_between(ks, w, eg, ej)
          +gi = Lay.gapif(rest, btw)
          +kh = Bool.pick(Nat, Lay.is_stretch(align), h, Nat.min(View.height(fv, kw), h))
          +rw = Nat.sub(w, Nat.add(lead, Nat.add(kw, gi)))
          hcat(blank_rows(h, lead),
            hcat(fit_rows(h, kw, List.append(&2, List<&2, Cell>, blank_rows(Lay.offset(align, kh, h), kw), fit_rows(kh, kw, draw.go(fv, kw, kh, Cont.No{})))),
              hcat(blank_rows(h, gi), fit_rows(h, rw, draw.go(Row{rest, gap, justify, align}, rw, h, Cont.Gap{btw})))))
    case Col{kids, gap, justify, align}:
      match kids:
        case Nil{}:
          Nil{}
        case Flex{fv, g, s, b} <> rest:
          +ks = {Flex{fv, g, s, b} <> rest : List<&2, Flex>}
          +eg = Cont.gap(cont, gap)
          +ej = Cont.just(cont, justify)
          +cw = Lay.cross_w(align, fv, w)
          +lead = Lay.col_lead(ks, w, h, eg, ej, align)
          +kh = Lay.col_first(ks, w, h, eg, align)
          +btw = Lay.col_between(ks, w, h, eg, ej, align)
          +gi = Lay.gapif(rest, btw)
          List.append(&2, List<&2, Cell>, blank_rows(lead, w),
            List.append(&2, List<&2, Cell>, Lay.indent(fit_rows(kh, cw, draw.go(fv, cw, kh, Cont.No{})), Lay.offset(align, cw, w)),
              List.append(&2, List<&2, Cell>, blank_rows(gi, w),
                draw.go(Col{rest, gap, justify, align}, w, Nat.sub(h, Nat.add(lead, Nat.add(kh, gi))), Cont.Gap{btw}))))
    case Pad{t, r, b, l, child}:
      +cw = Nat.sub(w, Nat.add(l, r))
      +ch = Nat.sub(h, Nat.add(t, b))
      List.append(&2, List<&2, Cell>, blank_rows(t, w),
        List.append(&2, List<&2, Cell>, Lay.indent(fit_rows(ch, cw, draw.go(child, cw, ch, Cont.No{})), l), blank_rows(b, w)))
    case Border{line, st, title, child}:
      +gl = Line.glyphs(line)
      List.append(&2, List<&2, Cell>, [Border.top(gl, st, title, w)],
        List.append(&2, List<&2, Cell>,
          Border.sides(fit_rows(Nat.sub(h, 2n), Nat.sub(w, 2n), draw.go(child, Nat.sub(w, 2n), Nat.sub(h, 2n), Cont.No{})), gl, st),
          [Border.bottom(gl, st, w)]))
    case Sized{sw, sh, child}:
      +cw = Nat.min(Size.of(sw, View.width(child), w), w)
      +ch = Nat.min(Size.of(sh, h, h), h)
      fit_rows(ch, cw, draw.go(child, cw, ch, Cont.No{}))

def draw(+v: View, +w: Nat, +h: Nat) -> List<&2, List<&2, Cell>>:
  draw.go(v, w, h, Cont.No{})

def render(+v: View, +w: Nat, +h: Nat) -> List<&2, List<&2, Cell>>:
  fit_rows(h, w, draw(v, w, h))

# Shorthands, with Ink's defaults

def txt(s: String) -> View:
  View.Txt{[Span.S{s}], Wrap.Word{}}

def spans(sp: List<&2, Span>) -> View:
  View.Txt{sp, Wrap.Word{}}

def Span.of(st: C.Style, s: String) -> Span:
  Span.In{st, [Span.S{s}]}

def Flex.of(v: View) -> Flex:
  Flex{v, 0n, 1n, Size.Auto{}}

def Flex.grow(v: View) -> Flex:
  Flex{v, 1n, 1n, Size.Auto{}}

def Row.of(kids: List<&2, Flex>) -> View:
  Row{kids, 0n, Justify.Start{}, Align.Stretch{}}

def Col.of(kids: List<&2, Flex>) -> View:
  Col{kids, 0n, Justify.Start{}, Align.Stretch{}}

def View.pad(+n: Nat, v: View) -> View:
  Pad{n, n, n, n, v}

# a margin is padding outside a border
def View.margin(t: Nat, r: Nat, b: Nat, l: Nat, v: View) -> View:
  Pad{t, r, b, l, v}

# Frames to strings
# -----------------
# A pen is how a stream shows looks: its colour level, and whether OSC 8
# links are written (on a terminal) or spelled out as text (url).

type Pen is Data:
  Pen{level: C.Level, links: Bool}

def Pen.plain() -> Pen:
  Pen{C.Level.None{}, False{}}

def Look.link(on: Bool, +url: String, +s: String, none: Bool) -> String:
  match none:
    case True{}:
      s
    case False{}:
      T.Tty.link(on, url, s)

def Look.paint(+p: Pen, k: Look, s: String) -> String:
  match p k:
    case Pen{l, on} Look.Of{st, +link}:
      Look.link(on, link, C.Style.paint(l, st, s), Str.same(link, ""))

def Cell.same_look(c: Cell, +k: Look) -> Bool:
  match c:
    case Cell.Of{g, k2}:
      Look.is_eq(k2, k)
    case Cell.Pad{}:
      True{}

# a row as runs of one look, each painted whole: the text of the run in
# progress is acc, its look k
def row_runs(cs: List<&2, Cell>, +p: Pen, +k: Look, +acc: String) -> String:
  match cs:
    case Nil{}:
      Look.paint(p, k, acc)
    case +c <> t:
      +same = Cell.same_look(c, k)
      Bool.pick(String, same, "", Look.paint(p, k, acc))
        ++ row_runs(t, p, Cell.look_of(c, k), Bool.pick(String, same, acc ++ Cell.str(c), Cell.str(c)))

def Row.paint(+p: Pen, cs: List<&2, Cell>) -> String:
  row_runs(cs, p, Look.plain(), "")

# the row r painted at line y, from a reset to a reset
def row_at(+p: Pen, +y: U32, r: List<&2, Cell>) -> String:
  T.Tty.goto(1, y) ++ T.Tty.reset() ++ Row.paint(p, r) ++ T.Tty.reset()

def Frame.show.go(rows: List<&2, List<&2, Cell>>, +p: Pen, +y: U32) -> List<&2, String>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      row_at(p, y, r) <> Frame.show.go(t, p, (y + 1 : U32))

# every row at its place
def Frame.show(+p: Pen, rows: List<&2, List<&2, Cell>>) -> String:
  String.concat(Frame.show.go(rows, p, 1))

def row_eq(a: List<&2, Cell>, b: List<&2, Cell>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case x <> xt y <> yt:
      Bool.and(Cell.is_eq(x, y), row_eq(xt, yt))
    case other1 other2:
      False{}

def Frame.diff.row.if(+p: Pen, +n: List<&2, Cell>, +y: U32, same: Bool) -> String:
  match same:
    case True{}:
      ""
    case False{}:
      row_at(p, y, n)

def Frame.diff.row(+p: Pen, +n: List<&2, Cell>, +q: List<&2, Cell>, +y: U32) -> String:
  Frame.diff.row.if(p, n, y, row_eq(n, q))

# the rows of next that differ from prev, each at its place; a row
# prev does not have is drawn
def Frame.diff.go(next: List<&2, List<&2, Cell>>, prev: List<&2, List<&2, Cell>>, +p: Pen, +y: U32) -> List<&2, String>:
  match next:
    case Nil{}:
      Nil{}
    case n <> nt:
      match prev:
        case Nil{}:
          row_at(p, y, n) <> Frame.diff.go(nt, Nil{}, p, (y + 1 : U32))
        case q <> qt:
          Frame.diff.row(p, n, q, y) <> Frame.diff.go(nt, qt, p, (y + 1 : U32))

def Frame.diff(+p: Pen, next: List<&2, List<&2, Cell>>, prev: List<&2, List<&2, Cell>>) -> String:
  String.concat(Frame.diff.go(next, prev, p, 1))

# The app
# -------
# What Tui.run (run.bend) loops over: a view of the state, and an
# update by the keys of a turn that answers the next state or None to
# quit.

type Tui<-M: Data> is Type:
  Tui{view: M -> View, update: List<&2, T.Key> -> M -> Maybe<&2, M>}

# folds a step over the keys of one turn, from a state or a quit: a
# helper for an update. Tui.fold(~M, ~step, ks, Some{m})
def Tui.fold(~M: Data, ~step: M -> T.Key -> Maybe<&2, M>, ks: List<&2, T.Key>, next: Maybe<&2, M>) -> Maybe<&2, M>:
  match ks:
    case Nil{}:
      next
    case k <> rest:
      match next:
        case None{}:
          None{}
        case Some{m}:
          Tui.fold(~M, ~step, rest, step(m, k))

# Inline frames
# -------------
# A CLI draws in the normal screen, under what it printed, as Ink does:
# a frame as tall as its content, the cursor resting at the start of the
# row below it. Lines above the frame that are printed once (Ink's
# Static) are the screen's done views; the live view is redrawn from
# the first line that changed. With no terminal, nothing moves the
# cursor: done lines are written as they come, the live frame once at
# the end.

def Row.empty(cs: List<&2, Cell>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case c <> t:
      False{}

def Row.keep(c: Cell, rest: List<&2, Cell>, gone: Bool) -> List<&2, Cell>:
  match gone:
    case True{}:
      Nil{}
    case False{}:
      c <> rest

# the row without its trailing blanks, which a terminal shows anyway
def Row.trim(cs: List<&2, Cell>) -> List<&2, Cell>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      +rest = Row.trim(t)
      Row.keep(c, rest, Bool.and(Row.empty(rest), Cell.is_eq(c, Cell.blank())))

def Rows.paint(+p: Pen, rows: List<&2, List<&2, Cell>>) -> List<&2, String>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      Row.paint(p, Row.trim(r)) <> Rows.paint(p, t)

# a view's lines at width w and its own height, painted
def View.lines(+p: Pen, +v: View, +w: Nat) -> List<&2, String>:
  Rows.paint(p, render(v, w, View.height(v, w)))

def Views.lines(+p: Pen, vs: List<&2, View>, +w: Nat) -> List<&2, String>:
  match vs:
    case Nil{}:
      Nil{}
    case v <> t:
      List.append(&2, String, View.lines(p, v, w), Views.lines(p, t, w))

type Screen is Data:
  Screen{done: List<&2, View>, live: View}

# what an inline renderer remembers: whether it may move the cursor,
# how it paints, the terminal's width and rows, the live lines on
# screen and how many done views it wrote
type Inline is Data:
  Inline{tty: Bool, pen: Pen, w: Nat, rows: Nat, prev: List<&2, String>, printed: Nat}

type Inline.Out is Data:
  Inline.Out{text: String, next: Inline}

def Inline.new(tty: Bool, p: Pen, w: Nat, rows: Nat) -> Inline:
  Inline{tty, p, w, rows, Nil{}, 0n}

def Inline.text(o: Inline.Out) -> String:
  match o:
    case Inline.Out{t, n}:
      t

def Inline.next(o: Inline.Out) -> Inline:
  match o:
    case Inline.Out{t, n}:
      n

def Inline.printed(st: Inline) -> Nat:
  match st:
    case Inline{tty, p, w, rows, prev, printed}:
      printed

def Str.cr() -> String:
  SCon{Chr{13}, SNil{}}

# a line break on a terminal: CR LF, so a line starts at column 1
# whatever the terminal's output modes
def Str.crlf() -> String:
  SCon{Chr{13}, SCon{Chr{10}, SNil{}}}

def Lines.join(ls: List<&2, String>, +nl: String) -> String:
  match ls:
    case Nil{}:
      ""
    case l <> t:
      l ++ nl ++ Lines.join(t, nl)

def Lines.first.at(same: Bool, rest: Maybe<&2, Nat>, +i: Nat) -> Maybe<&2, Nat>:
  match same:
    case True{}:
      rest
    case False{}:
      Some{i}

# the index of the first line where next differs from prev, counting
# from i; None when they are the same lines
def Lines.first(prev: List<&2, String>, next: List<&2, String>, +i: Nat) -> Maybe<&2, Nat>:
  match prev next:
    case Nil{} Nil{}:
      None{}
    case Nil{} n <> nt:
      Some{i}
    case p <> pt Nil{}:
      Some{i}
    case p <> pt n <> nt:
      Lines.first.at(Str.same(p, n), Lines.first(pt, nt, 1n+i), i)

# the last keep lines
def Lines.last(+ls: List<&2, String>, +keep: Nat) -> List<&2, String>:
  List.drop(&2, String, ls, Nat.sub(List.length(&2, String, ls), keep))

# s inside synchronized output; nothing when s is empty
def Inline.sync(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      T.Tty.sync(True{}) ++ SCon{h, t} ++ T.Tty.sync(False{})

# from the row below a frame of n lines up to its row k, column 1
def Inline.rise(+n: Nat, +k: Nat) -> String:
  T.Tty.up(U32.from_nat(Nat.sub(n, k))) ++ Str.cr()

def Inline.redraw(+n: Nat, at: Maybe<&2, Nat>, +next: List<&2, String>) -> String:
  match at:
    case None{}:
      ""
    case Some{+k}:
      Inline.rise(n, k) ++ T.Tty.erase_down() ++ Lines.join(List.drop(&2, String, next, k), Str.crlf())

def Inline.write.tty(+prev: List<&2, String>, fresh: List<&2, String>, +next: List<&2, String>) -> String:
  match fresh:
    case Nil{}:
      Inline.sync(Inline.redraw(List.length(&2, String, prev), Lines.first(prev, next, 0n), next))
    case f <> ft:
      Inline.sync(Inline.rise(List.length(&2, String, prev), 0n) ++ T.Tty.erase_down()
        ++ Lines.join(f <> ft, Str.crlf()) ++ Lines.join(next, Str.crlf()))

# what a draw writes, from the live lines on screen (prev), the done
# lines not yet written (fresh) and the live lines now (next): on a
# terminal, the fresh lines go above a whole new frame, or else the
# frame is redrawn from its first changed line; with no terminal, the
# fresh lines alone
def Inline.write(tty: Bool, +prev: List<&2, String>, fresh: List<&2, String>, +next: List<&2, String>) -> String:
  match tty:
    case True{}:
      Inline.write.tty(prev, fresh, next)
    case False{}:
      Lines.join(fresh, "\n")

def Inline.fresh(+printed: Nat, done: List<&2, View>) -> List<&2, View>:
  List.drop(&2, View, done, printed)

# a frame taller than the terminal shows its last rows - 1 lines: rows
# that scrolled away cannot be reached to be redrawn
def Inline.clip(+rows: Nat, ls: List<&2, String>) -> List<&2, String>:
  Lines.last(ls, Nat.sub(Nat.max(rows, 2n), 1n))

def Inline.draw(st: Inline, s: Screen) -> Inline.Out:
  match st s:
    case Inline{+tty, +p, +w, +rows, prev, printed} Screen{+done, live}:
      +next = Inline.clip(rows, View.lines(p, live, w))
      Inline.Out{Inline.write(tty, prev, Views.lines(p, Inline.fresh(printed, done), w), next),
                 Inline{tty, p, w, rows, next, List.length(&2, View, done)}}

# what ends the output: the last done lines and the whole final frame,
# unclipped, so the scrollback holds all of it
def Inline.end.write(tty: Bool, +prev: List<&2, String>, +fresh: List<&2, String>, +all: List<&2, String>) -> String:
  match tty:
    case True{}:
      Inline.write.tty(prev, fresh, all)
    case False{}:
      Lines.join(List.append(&2, String, fresh, all), "\n")

def Inline.end(st: Inline, s: Screen) -> String:
  match st s:
    case Inline{tty, +p, +w, rows, prev, printed} Screen{done, live}:
      Inline.end.write(tty, prev, Views.lines(p, Inline.fresh(printed, done), w), View.lines(p, live, w))

# a new size: after a change of width the old frame may have been
# reflowed by the terminal, so it is erased and drawn again whole
def Inline.resize.go(tty: Bool, p: Pen, +prev: List<&2, String>, printed: Nat, +w2: Nat, +rows2: Nat, clear: Bool) -> Inline.Out:
  match clear:
    case True{}:
      Inline.Out{Inline.rise(List.length(&2, String, prev), 0n) ++ T.Tty.erase_down(), Inline{tty, p, w2, rows2, Nil{}, printed}}
    case False{}:
      Inline.Out{"", Inline{tty, p, w2, rows2, prev, printed}}

def Inline.resize.at(st: Inline, +w2: Nat, +rows2: Nat, same: Bool) -> Inline.Out:
  match st:
    case Inline{+tty, p, w, rows, +prev, printed}:
      Inline.resize.go(tty, p, prev, printed, w2, rows2, Bool.and(tty, Bool.not(same)))

def Inline.resize(+st: Inline, +w2: Nat, +rows2: Nat) -> Inline.Out:
  match st:
    case Inline{tty, p, w, rows, prev, printed}:
      Inline.resize.at(st, w2, rows2, Nat.is_eq(w, w2))

# The CLI app
# -----------
# What Cli.run (run.bend) loops over. Its events: the keys of a read,
# a tick when nothing came within the tick, a message the work posted,
# the work's end, and Ctrl-C. An update answers Go to go on, End to
# stop; the loop answers the last state.

type Ev<-Msg: Data> is Data:
  Ev.Keys{ks: List<&2, T.Key>}
  Ev.Tick{}
  Ev.Msg{m: Msg}
  Ev.Done{}
  Ev.Cancel{}

type Step<-M: Data> is Data:
  Step.Go{m: M}
  Step.End{m: M}

type Cli<-M: Data, -Msg: Data> is Type:
  Cli{view: M -> Screen, update: Ev<Msg> -> M -> Step<M>, keys: M -> Bool}

# A sample
# --------

def Frame.plain(rows: List<&2, List<&2, Cell>>) -> List<&2, String>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      Row.paint(Pen.plain(), r) <> Frame.plain(t)

def main() -> List<&2, String>:
  Frame.plain(render(Boxed{"tui", Above{Menu{["one", "两个", "three"], 1n}, Progress{1n, 3n, Style.plain()}, 3n}}, 12n, 6n))
