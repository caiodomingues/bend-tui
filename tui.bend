# bend-tui: terminal interfaces for Bend 2, on bend-tty. A View is a
# tree of widgets; render lays it out into a Frame, exactly h rows of
# w cells whatever the view (LAWS.bend proves it); Frame.diff writes
# only the rows that changed; Tui.run is the loop, in the shape of
# Base's App.run: a state, a view of it, an update by the keys read.
#
#   bend tui.bend        # checks; main renders a small tree as text
#
# One cell is one column: no wide characters or emoji widths.

import Base
import ../bend-tty/tty.bend as T

# Cells
# -----

# fg and bg are 256-color codes; 256 is the terminal's default
type Style is Data:
  Style{fg: U32, bg: U32, bold: Bool}

def Style.plain() -> Style:
  Style{256, 256, False{}}

def Style.fg(c: U32) -> Style:
  Style{c, 256, False{}}

def Style.bold(c: U32) -> Style:
  Style{c, 256, True{}}

# selected rows: black on white
def Style.inverse() -> Style:
  Style{0, 7, False{}}

def Bool.same(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case other1 other2:
      False{}

def Style.is_eq(a: Style, b: Style) -> Bool:
  match a b:
    case Style{f1, b1, o1} Style{f2, b2, o2}:
      Bool.and(U32.is_eq(f1, f2), Bool.and(U32.is_eq(b1, b2), Bool.same(o1, o2)))

# ch is a Unicode code point
type Cell is Data:
  Cell{ch: U32, st: Style}

def Cell.blank() -> Cell:
  Cell{32, Style.plain()}

def Cell.is_eq(a: Cell, b: Cell) -> Bool:
  match a b:
    case Cell{c1, s1} Cell{c2, s2}:
      Bool.and(U32.is_eq(c1, c2), Style.is_eq(s1, s2))

# a string's characters as cells of one style
def Cell.text(+st: Style, s: String) -> List<&2, Cell>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      Cell{c, st} <> Cell.text(st, t)

# Fit
# ---
# fit cuts or pads a row to exactly w cells, and fit_rows a list of
# rows to exactly h rows of w cells, each by recursion on the size
# alone, so the count is structural: the laws fit_len and fit_rows_len
# are one induction each, and every widget's frame goes through them.

def fit(w: Nat, cs: List<&2, Cell>) -> List<&2, Cell>:
  match w:
    case 0n:
      Nil{}
    case 1n+p:
      match cs:
        case Nil{}:
          Cell.blank() <> fit(p, Nil{})
        case c <> t:
          c <> fit(p, t)

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
  Text{st: Style, s: String}                    # one row
  Lines{st: Style, ls: List<&2, String>}        # a row per string
  Fill{c: Cell}                                 # the whole area
  Above{top: View, bottom: View, rows: Nat}     # top gets rows rows, bottom the rest
  Below{top: View, bottom: View, rows: Nat}     # bottom gets rows rows, top the rest
  Beside{left: View, right: View, cols: Nat}    # left gets cols columns, right the rest
  After{left: View, right: View, cols: Nat}     # right gets cols columns, left the rest
  Boxed{title: String, child: View}             # a border with a title; the child inside
  Menu{items: List<&2, String>, sel: Nat, top: Nat}   # a list; item sel highlighted; scrolled to top
  Input{text: String, cursor: Nat}              # one row of text with the cursor cell inverse
  Progress{done: Nat, total: Nat, st: Style}    # one row, filled to done / total

# rows placed side by side: each left row followed by its right row
def hcat(ls: List<&2, List<&2, Cell>>, rs: List<&2, List<&2, Cell>>) -> List<&2, List<&2, Cell>>:
  match ls rs:
    case Nil{} r:
      Nil{}
    case l <> lt Nil{}:
      Nil{}
    case l <> lt r <> rt:
      List.append(&2, Cell, l, r) <> hcat(lt, rt)

def lines(+st: Style, ls: List<&2, String>) -> List<&2, List<&2, Cell>>:
  match ls:
    case Nil{}:
      Nil{}
    case s <> t:
      Cell.text(st, s) <> lines(st, t)

# the menu's rows from item i on: the selected one inverse
def menu_rows(items: List<&2, String>, +i: Nat, +sel: Nat) -> List<&2, List<&2, Cell>>:
  match items:
    case Nil{}:
      Nil{}
    case s <> t:
      Cell.text(Bool.pick(Style, Nat.is_eq(i, sel), Style.inverse(), Style.plain()), s) <> menu_rows(t, 1n+i, sel)

# the input's cells: the text, with the cell at the cursor inverse
# (a blank one past the end)
def input_cells(+cs: List<&2, Cell>, +cursor: Nat) -> List<&2, Cell>:
  match cs cursor:
    case Nil{} 0n:
      [Cell{32, Style.inverse()}]
    case Nil{} 1n+p:
      Nil{}
    case Cell{ch, st} <> t 0n:
      Cell{ch, Style.inverse()} <> input_cells(t, 0n)
    case c <> t 1n+p:
      c <> input_cells(t, p)

# n cells of ch in st
def cells_of(n: Nat, +ch: U32, +st: Style) -> List<&2, Cell>:
  List.replicate(Cell, n, Cell{ch, st})

# the filled part of a bar: w * done / total cells, total at least 1
def bar_cells(+w: Nat, +done: Nat, +total: Nat, +st: Style) -> List<&2, Cell>:
  +n = Nat.div(Nat.mul(w, Nat.min(done, total)), Nat.max(total, 1n))
  List.append(&2, Cell, cells_of(n, 9608, st), cells_of(Nat.sub(w, n), 9617, st))

# a box: a top row with the title, the child's rows between bars, a
# bottom row. Box-drawing code points: 9484 9472 9488 9474 9492 9496
def box_top(+w: Nat, title: String) -> List<&2, Cell>:
  fit(w, List.append(&2, Cell, [Cell{9484, Style.plain()}], List.append(&2, Cell, Cell.text(Style.plain(), title), cells_of(w, 9472, Style.plain()))))

def box_bottom(+w: Nat) -> List<&2, Cell>:
  fit(w, Cell{9492, Style.plain()} <> cells_of(w, 9472, Style.plain()))

def box_side(rows: List<&2, List<&2, Cell>>) -> List<&2, List<&2, Cell>>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      List.append(&2, Cell, Cell{9474, Style.plain()} <> r, [Cell{9474, Style.plain()}]) <> box_side(t)

# the box's corners on a top or bottom row: the last cell replaced
def box_corner(+w: Nat, row: List<&2, Cell>, +corner: U32) -> List<&2, Cell>:
  List.append(&2, Cell, List.take(&2, Cell, row, Nat.sub(w, 1n)), [Cell{corner, Style.plain()}])

# Render
# ------
# draw is one recursive def over the view, each arm the rows a widget
# wants, with every child rendered through fit_rows; render fits the
# whole, so a frame is h rows of w cells whatever the view, and the
# laws render_rows and render_cols are the fit lemmas applied

def draw(+v: View, +w: Nat, +h: Nat) -> List<&2, List<&2, Cell>>:
  match v:
    case Text{st, s}:
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
    case Boxed{title, child}:
      List.append(&2, List<&2, Cell>,
        [box_corner(w, box_top(w, title), 9488)],
        List.append(&2, List<&2, Cell>,
          box_side(fit_rows(Nat.sub(h, 2n), Nat.sub(w, 2n), draw(child, Nat.sub(w, 2n), Nat.sub(h, 2n)))),
          [box_corner(w, box_bottom(w), 9496)]))
    case Menu{items, sel, top}:
      menu_rows(List.drop(&2, String, items, top), top, sel)
    case Input{text, cursor}:
      [input_cells(Cell.text(Style.plain(), text), cursor)]
    case Progress{done, total, st}:
      [bar_cells(w, done, total, st)]

def render(+v: View, +w: Nat, +h: Nat) -> List<&2, List<&2, Cell>>:
  fit_rows(h, w, draw(v, w, h))

# Frames to strings
# -----------------

def Style.esc.fg(+c: U32, dflt: Bool) -> String:
  match dflt:
    case True{}:
      ""
    case False{}:
      T.Tty.fg(c)

def Style.esc.bg(+c: U32, dflt: Bool) -> String:
  match dflt:
    case True{}:
      ""
    case False{}:
      T.Tty.bg(c)

def Style.esc.bold(b: Bool) -> String:
  match b:
    case True{}:
      T.Tty.bold()
    case False{}:
      ""

# the escape that sets st after prev, or nothing when equal
def Style.esc(+st: Style) -> String:
  match st:
    case Style{fg, bg, bold}:
      T.Tty.reset() ++ Style.esc.fg(fg, U32.is_eq(fg, 256)) ++ Style.esc.bg(bg, U32.is_eq(bg, 256)) ++ Style.esc.bold(bold)

def Style.change(+prev: Style, +st: Style, same: Bool) -> String:
  match same:
    case True{}:
      ""
    case False{}:
      Style.esc(st)

# a row's cells as text, a style escape only where the style changes;
# acc gathers the pieces reversed
def row_text(+cs: List<&2, Cell>, +prev: Style, acc: List<&2, String>) -> String:
  match cs:
    case Nil{}:
      String.join(List.reverse(&2, String, acc), "")
    case Cell{ch, st} <> t:
      row_text(t, st, SCon{Chr{ch}, ""} <> Style.change(prev, st, Style.is_eq(prev, st)) <> acc)

def row_string(cs: List<&2, Cell>) -> String:
  row_text(cs, Style.plain(), [T.Tty.reset()])

# every row at its place: goto, the row, a reset
def Frame.show.go(rows: List<&2, List<&2, Cell>>, +y: U32) -> List<&2, String>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      (T.Tty.goto(1, y) ++ row_string(r) ++ T.Tty.reset()) <> Frame.show.go(t, (y + 1 : U32))

def Frame.show(rows: List<&2, List<&2, Cell>>) -> String:
  String.join(Frame.show.go(rows, 1), "")

def row_eq(a: List<&2, Cell>, b: List<&2, Cell>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case x <> xt y <> yt:
      Bool.and(Cell.is_eq(x, y), row_eq(xt, yt))
    case other1 other2:
      False{}

def Frame.diff.row.if(+n: List<&2, Cell>, +y: U32, same: Bool) -> String:
  match same:
    case True{}:
      ""
    case False{}:
      T.Tty.goto(1, y) ++ row_string(n) ++ T.Tty.reset()

def Frame.diff.row(+n: List<&2, Cell>, +p: List<&2, Cell>, +y: U32) -> String:
  Frame.diff.row.if(n, y, row_eq(n, p))

# the rows of next that differ from prev, each at its place; a row
# prev does not have is drawn
def Frame.diff.go(next: List<&2, List<&2, Cell>>, prev: List<&2, List<&2, Cell>>, +y: U32) -> List<&2, String>:
  match next:
    case Nil{}:
      Nil{}
    case n <> nt:
      match prev:
        case Nil{}:
          (T.Tty.goto(1, y) ++ row_string(n) ++ T.Tty.reset()) <> Frame.diff.go(nt, Nil{}, (y + 1 : U32))
        case p <> pt:
          Frame.diff.row(n, p, y) <> Frame.diff.go(nt, pt, (y + 1 : U32))

def Frame.diff(next: List<&2, List<&2, Cell>>, prev: List<&2, List<&2, Cell>>) -> String:
  String.join(Frame.diff.go(next, prev, 1), "")

# The loop
# --------
# Tui.run(~M, ~app, m0, ms): each turn renders the view of the state
# at the terminal's size, writes what changed, reads the keys within
# ms, and hands them to update, which answers the next state or None
# to quit. Like App.run, the loop is a template over a closed app, and
# the helpers take the rest of the loop as a closure, called once.

type Tui<-M: Data> is Type:
  Tui{view: M -> View, update: List<&2, T.Key> -> M -> Maybe<&2, M>}

def Tui.quit() -> IO(Unit):
  do IO<Unit>:
    IO.write(T.Tty.cursor(True{}) ++ T.Tty.alt(False{}) ++ T.Tty.reset())
    T.Tty.raw(False{})

def Tui.next(-M: Data, frame: List<&2, List<&2, Cell>>, next: Maybe<&2, M>, rest: List<&2, List<&2, Cell>> -> M -> IO(Unit)) -> IO(Unit):
  match next:
    case None{}:
      Tui.quit()
    case Some{m}:
      rest(frame, m)

def Tui.read(-M: Data, frame: List<&2, List<&2, Cell>>, update: List<&2, T.Key> -> M -> Maybe<&2, M>, m: M, got: Maybe<&2, List<&2, U32>>, rest: List<&2, List<&2, Cell>> -> M -> IO(Unit)) -> IO(Unit):
  match got:
    case None{}:
      Tui.quit()
    case Some{bs}:
      Tui.next(M, frame, update(T.Tty.keys(bs), m), rest)

def Tui.step(-M: Data, app: Tui<M>, wh: U32 & U32, prev: List<&2, List<&2, Cell>>, +m: M, +ms: U32, rest: List<&2, List<&2, Cell>> -> M -> IO(Unit)) -> IO(Unit):
  Tui{view, update} = app
  (w, h) = wh
  +frame = render(view(m), U32.to_nat(w), U32.to_nat(h))
  do IO<Unit>:
    IO.write(Frame.diff(frame, prev))
    got : Maybe<&2, List<&2, U32>> <- T.Tty.read(ms, 4096)
    Tui.read(M, frame, update, m, got, rest)

def Tui.loop(~M: Data, ~app: Tui<M>, fuel: Nat, prev: List<&2, List<&2, Cell>>, m: M, +ms: U32) -> IO(Unit):
  match fuel:
    case 0n:
      Tui.quit()
    case 1n+f:
      do IO<Unit>:
        wh : U32 & U32 <- T.Tty.size()
        Tui.step(M, app, wh, prev, m, ms, p2 => m2 => Tui.loop(~M, ~app, f, p2, m2, ms))

def Tui.run(~M: Data, ~app: Tui<M>, m0: M, ms: U32) -> IO(Unit):
  do IO<Unit>:
    T.Tty.raw(True{})
    IO.write(T.Tty.alt(True{}) ++ T.Tty.cursor(False{}) ++ T.Tty.clear())
    Tui.loop(~M, ~app, U32.to_nat(4294967295), Nil{}, m0, ms)

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

# A sample
# --------

def Frame.plain.row(cs: List<&2, Cell>) -> List<&2, Char>:
  match cs:
    case Nil{}:
      Nil{}
    case Cell{ch, st} <> t:
      Chr{ch} <> Frame.plain.row(t)

def Frame.plain(rows: List<&2, List<&2, Cell>>) -> List<&2, String>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      String.from_list(Frame.plain.row(r)) <> Frame.plain(t)

def main() -> List<&2, String>:
  Frame.plain(render(Boxed{"tui", Above{Menu{["one", "two", "three"], 1n, 0n}, Progress{1n, 3n, Style.plain()}, 3n}}, 12n, 6n))
