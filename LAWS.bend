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
  for +f : List<&2, List<&2, U.Cell>>
  {U.Frame.diff(f, f) == "" : String}
