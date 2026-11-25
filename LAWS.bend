# bend-tui: the laws. A frame is exactly h rows of w cells, whatever
# the view: the bug a terminal UI cannot have here is a row of the
# wrong width or a frame of the wrong height. Both are stated for
# every view, size and state, not for examples.

import Base
import ./tui.bend as U

# AllLen(w, rows): every row has w cells
def AllLen(+w: Nat, rows: List<&2, List<&2, U.Cell>>) -> Type:
  match rows:
    case Nil{}:
      Unit
    case r <> t:
      ({List.length(&2, U.Cell, r) == w : Nat} & AllLen(w, t))

# LAW: fit gives exactly w cells
law fit_len:
  for +w  : Nat
  for +cs : List<&2, U.Cell>
  {List.length(&2, U.Cell, U.fit(w, cs)) == w : Nat}

# LAW: fit_rows gives exactly h rows
law fit_rows_len:
  for +h    : Nat
  for +w    : Nat
  for +rows : List<&2, List<&2, U.Cell>>
  {List.length(&2, List<&2, U.Cell>, U.fit_rows(h, w, rows)) == h : Nat}

# LAW: every row fit_rows gives has w cells
law fit_rows_cols:
  for +h    : Nat
  for +w    : Nat
  for +rows : List<&2, List<&2, U.Cell>>
  AllLen(w, U.fit_rows(h, w, rows))

# LAW: a rendered frame has h rows, for every view
law render_rows:
  for +v : U.View
  for +w : Nat
  for +h : Nat
  {List.length(&2, List<&2, U.Cell>, U.render(v, w, h)) == h : Nat}

# LAW: every row of a rendered frame has w cells, for every view
law render_cols:
  for +v : U.View
  for +w : Nat
  for +h : Nat
  AllLen(w, U.render(v, w, h))

# LAW: a frame diffed against itself writes nothing: an idle screen
# costs no output
law diff_self:
  for +p : U.Pen
  for +f : List<&2, List<&2, U.Cell>>
  {U.Frame.diff(p, f, f) == "" : String}

# LAW: two lists of the same lines have no first difference
law lines_first_same:
  for +ls : List<&2, String>
  for +i  : Nat
  {U.Lines.first(ls, ls, i) == None{} : Maybe<&2, Nat>}

# LAW: drawing a screen again, unchanged, writes nothing: an idle CLI
# costs no output, on a terminal or not
law inline_same:
  for +st : U.Inline
  for +s  : U.Screen
  {U.Inline.text(U.Inline.draw(U.Inline.next(U.Inline.draw(st, s)), s)) == "" : String}

# LAW: after a draw, the done views still to write are exactly those
# added since: each done view is written once
law static_once:
  for +st   : U.Inline
  for +done : List<&2, U.View>
  for +more : List<&2, U.View>
  for +live : U.View
  {U.Inline.fresh(U.Inline.printed(U.Inline.next(U.Inline.draw(st, U.Screen{done, live}))), List.append(&2, U.View, done, more)) == more : List<&2, U.View>}

# LAW: with no terminal, a draw writes the new done lines and nothing
# else: no cursor movement, no live frame
law pipe_plain:
  for +prev  : List<&2, String>
  for +fresh : List<&2, String>
  for +next  : List<&2, String>
  {U.Inline.write(False{}, prev, fresh, next) == U.Lines.join(fresh, "\n") : String}

# LAW: with no terminal, a draw writes the done lines not yet written,
# joined by line breaks, and nothing else: no cursor movement, no live
# frame, whatever the screen
law pipe_draw:
  for +p : U.Pen
  for +w : Nat
  for +rows : Nat
  for +prev : List<&2, String>
  for +printed : Nat
  for +up : Nat
  for +cur : String
  for +s : U.Screen
  {U.Inline.text(U.Inline.draw(U.Inline{False{}, p, w, rows, prev, printed, up, cur}, s)) == U.Lines.join(U.Views.lines(p, U.Inline.fresh(printed, U.Screen.done(s)), w), "\n") : String}

# LAW: with no terminal, the end writes the done lines left and the
# whole final frame, joined by line breaks, and nothing else
law pipe_end:
  for +p : U.Pen
  for +w : Nat
  for +rows : Nat
  for +prev : List<&2, String>
  for +printed : Nat
  for +up : Nat
  for +cur : String
  for +s : U.Screen
  {U.Inline.end(U.Inline{False{}, p, w, rows, prev, printed, up, cur}, s) == U.Lines.join(List.append(&2, String, U.Views.lines(p, U.Inline.fresh(printed, U.Screen.done(s)), w), U.View.lines(p, U.Screen.live(s), w)), "\n") : String}

# LAW: a percent basis is a share of the whole row, for every child: two
# halves of 20 columns are 10 and 10
law pct_halves:
  {U.Frame.plain(U.render(U.Row{[U.Flex{U.Fill{U.Cell.Of{"a", U.Look.plain()}}, 0n, 1n, U.Size.Pct{50n}}, U.Flex{U.Fill{U.Cell.Of{"b", U.Look.plain()}}, 0n, 1n, U.Size.Pct{50n}}], 0n, U.Justify.Start{}, U.Align.Stretch{}}, 20n, 1n)) == ["aaaaaaaaaabbbbbbbbbb"] : List<&2, String>}
