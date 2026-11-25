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

# Render
# ------
# draw is one recursive def over the view, each arm the rows a widget
# wants, with every child rendered through fit_rows; render fits the
# whole, so a frame is h rows of w cells whatever the view, and the
# laws render_rows and render_cols are the fit lemmas applied

def draw(+v: View, +w: Nat, +h: Nat) -> List<&2, List<&2, Cell>>:
  match v:
    case View.Text{st, s}:
      [Cell.text(st, s)]
    case Lines{st, ls}:
      lines(st, ls)
    case Fill{c}:
      List.replicate(List<&2, Cell>, h, List.replicate(Cell, w, c))
    case Above{top, bottom, rows}:
      List.append(&2, List<&2, Cell>,
        fit_rows(rows, w, draw(top, w, rows)),
        fit_rows(Nat.sub(h, rows), w, draw(bottom, w, Nat.sub(h, rows))))
    case Below{top, bottom, rows}:
      List.append(&2, List<&2, Cell>,
        fit_rows(Nat.sub(h, rows), w, draw(top, w, Nat.sub(h, rows))),
        fit_rows(rows, w, draw(bottom, w, rows)))
    case Beside{left, right, cols}:
      hcat(fit_rows(h, cols, draw(left, cols, h)), fit_rows(h, Nat.sub(w, cols), draw(right, Nat.sub(w, cols), h)))
    case After{left, right, cols}:
      hcat(fit_rows(h, Nat.sub(w, cols), draw(left, Nat.sub(w, cols), h)), fit_rows(h, cols, draw(right, cols, h)))
    case Split{left, right, num, den}:
      +cols = Nat.div(Nat.mul(w, num), Nat.max(den, 1n))
      hcat(fit_rows(h, cols, draw(left, cols, h)), fit_rows(h, Nat.sub(w, cols), draw(right, Nat.sub(w, cols), h)))
    case Stack{top, bottom, num, den}:
      +rows = Nat.div(Nat.mul(h, num), Nat.max(den, 1n))
      List.append(&2, List<&2, Cell>,
        fit_rows(rows, w, draw(top, w, rows)),
        fit_rows(Nat.sub(h, rows), w, draw(bottom, w, Nat.sub(h, rows))))
    case Boxed{title, child}:
      List.append(&2, List<&2, Cell>,
        [box_corner(w, box_top(w, title), 9488)],
        List.append(&2, List<&2, Cell>,
          box_side(fit_rows(Nat.sub(h, 2n), Nat.sub(w, 2n), draw(child, Nat.sub(w, 2n), Nat.sub(h, 2n)))),
          [box_corner(w, box_bottom(w), 9496)]))
    case Menu{items, sel}:
      menu_rows(List.drop(&2, String, items, menu_top(sel, h)), menu_top(sel, h), sel)
    case Input{text, cursor}:
      [input_cells(Cell.text(Style.plain(), text), cursor)]
    case Progress{done, total, st}:
      [bar_cells(w, done, total, st)]

def render(+v: View, +w: Nat, +h: Nat) -> List<&2, List<&2, Cell>>:
  fit_rows(h, w, draw(v, w, h))

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

# the rows a view takes at width w when nothing bounds its height
def View.height(+v: View, +w: Nat) -> Nat:
  match v:
    case View.Text{st, s}:
      1n
    case Lines{st, ls}:
      List.length(&2, String, ls)
    case Fill{c}:
      1n
    case Above{top, bottom, rows}:
      Nat.add(rows, View.height(bottom, w))
    case Below{top, bottom, rows}:
      Nat.add(View.height(top, w), rows)
    case Beside{left, right, cols}:
      Nat.max(View.height(left, cols), View.height(right, Nat.sub(w, cols)))
    case After{left, right, cols}:
      Nat.max(View.height(left, Nat.sub(w, cols)), View.height(right, cols))
    case Split{left, right, num, den}:
      +cols = Nat.div(Nat.mul(w, num), Nat.max(den, 1n))
      Nat.max(View.height(left, cols), View.height(right, Nat.sub(w, cols)))
    case Stack{top, bottom, num, den}:
      Nat.add(View.height(top, w), View.height(bottom, w))
    case Boxed{title, child}:
      2n+View.height(child, Nat.sub(w, 2n))
    case Menu{items, sel}:
      List.length(&2, String, items)
    case Input{text, cursor}:
      1n
    case Progress{done, total, st}:
      1n

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
