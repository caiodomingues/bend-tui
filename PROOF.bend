# bend-tui: the proofs. fit and fit_rows recurse on the size, so each
# count is one induction on it; render is fit_rows of draw, so its
# laws are the fit_rows laws applied to whatever draw gives.

import Base
import ../bend-tty/color.bend as C
import ./tui.bend as U
import ./LAWS.bend as Laws
import ../bend-lemmas/string.bend as S

def Laws.fit_len(w, cs):
  match w:
    case 0n:
      {==}
    case 1n+p:
      match cs:
        case Nil{}:
          %Laws.fit_len(p, Nil{}) : {1n+List.length(&2, U.Cell, U.fit(p, Nil{})) == 1n+_ : Nat}
          {==}
        case c <> t:
          %Laws.fit_len(p, t) : {1n+List.length(&2, U.Cell, U.fit(p, t)) == 1n+_ : Nat}
          {==}

def Laws.fit_rows_len(h, w, rows):
  match h:
    case 0n:
      {==}
    case 1n+p:
      match rows:
        case Nil{}:
          %Laws.fit_rows_len(p, w, Nil{}) : {1n+List.length(&2, List<&2, U.Cell>, U.fit_rows(p, w, Nil{})) == 1n+_ : Nat}
          {==}
        case r <> t:
          %Laws.fit_rows_len(p, w, t) : {1n+List.length(&2, List<&2, U.Cell>, U.fit_rows(p, w, t)) == 1n+_ : Nat}
          {==}

def Laws.fit_rows_cols(h, w, rows):
  match h:
    case 0n:
      Unit{}
    case 1n+p:
      match rows:
        case Nil{}:
          (Laws.fit_len(w, Nil{}), Laws.fit_rows_cols(p, w, Nil{}))
        case r <> t:
          (Laws.fit_len(w, r), Laws.fit_rows_cols(p, w, t))

def Laws.render_rows(v, w, h):
  Laws.fit_rows_len(h, w, U.draw(v, w, h))

def Laws.render_cols(v, w, h):
  Laws.fit_rows_cols(h, w, U.draw(v, w, h))

# diff_self: every row compares equal to itself (reflexivity of the
# comparisons, from U32.cmp and Bool.cmp up), so every row's diff is
# "", and a concat of empty strings is empty. AllEmpty carries the
# second fact.

def u32_eq_refl(+x: U32) -> {U32.is_eq(x, x) == True{} : Bool}:
  %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, S.u32_cmp_refl(x)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

# both sides of an and are true
def and_tt(+a: Bool, +b: Bool, ea: {a == True{} : Bool}, eb: {b == True{} : Bool}) -> {Bool.and(a, b) == True{} : Bool}:
  %Equal.sym(Bool, a, True{}, ea) : {Bool.and(_, b) == True{} : Bool}
  %Equal.sym(Bool, b, True{}, eb) : {Bool.and(True{}, _) == True{} : Bool}
  {==}

def bool_same_refl(+b: Bool) -> {U.Bool.same(b, b) == True{} : Bool}:
  %Equal.sym(Cmp, Bool.cmp(b, b), EQ{}, S.bool_cmp_refl(b)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

def str_same_refl(+s: String) -> {U.Str.same(s, s) == True{} : Bool}:
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      and_tt(U32.is_eq(x, x), U.Str.same(t, t), u32_eq_refl(x), str_same_refl(t))

def color_same_refl(+c: C.Color) -> {U.Color.same(c, c) == True{} : Bool}:
  match c:
    case C.Color.Default{}:
      {==}
    case C.Color.Basic{x}:
      u32_eq_refl(x)
    case C.Color.Ansi256{x}:
      u32_eq_refl(x)
    case C.Color.Rgb{r, g, b}:
      and_tt(U32.is_eq(r, r), Bool.and(U32.is_eq(g, g), U32.is_eq(b, b)), u32_eq_refl(r),
        and_tt(U32.is_eq(g, g), U32.is_eq(b, b), u32_eq_refl(g), u32_eq_refl(b)))

# the seven modifiers of a style, compared with themselves
def mods_refl(+x: Bool, +y: Bool, +z: Bool, +u: Bool, +v: Bool, +h: Bool, +t: Bool)
  -> {Bool.and(U.Bool.same(x, x), Bool.and(U.Bool.same(y, y), Bool.and(U.Bool.same(z, z),
       Bool.and(U.Bool.same(u, u), Bool.and(U.Bool.same(v, v), Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))) == True{} : Bool}:
  %Equal.sym(Bool, U.Bool.same(x, x), True{}, bool_same_refl(x)) : {Bool.and(_, Bool.and(U.Bool.same(y, y), Bool.and(U.Bool.same(z, z),
       Bool.and(U.Bool.same(u, u), Bool.and(U.Bool.same(v, v), Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))) == True{} : Bool}
  %Equal.sym(Bool, U.Bool.same(y, y), True{}, bool_same_refl(y)) : {Bool.and(True{}, Bool.and(_, Bool.and(U.Bool.same(z, z),
       Bool.and(U.Bool.same(u, u), Bool.and(U.Bool.same(v, v), Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))) == True{} : Bool}
  %Equal.sym(Bool, U.Bool.same(z, z), True{}, bool_same_refl(z)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_,
       Bool.and(U.Bool.same(u, u), Bool.and(U.Bool.same(v, v), Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))) == True{} : Bool}
  %Equal.sym(Bool, U.Bool.same(u, u), True{}, bool_same_refl(u)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{},
       Bool.and(_, Bool.and(U.Bool.same(v, v), Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))) == True{} : Bool}
  %Equal.sym(Bool, U.Bool.same(v, v), True{}, bool_same_refl(v)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{},
       Bool.and(True{}, Bool.and(_, Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))) == True{} : Bool}
  %Equal.sym(Bool, U.Bool.same(h, h), True{}, bool_same_refl(h)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{},
       Bool.and(True{}, Bool.and(True{}, Bool.and(_, U.Bool.same(t, t))))))) == True{} : Bool}
  %Equal.sym(Bool, U.Bool.same(t, t), True{}, bool_same_refl(t)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{},
       Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _)))))) == True{} : Bool}
  {==}

def style_same_refl(+s: C.Style) -> {U.Style.same(s, s) == True{} : Bool}:
  match s:
    case C.Style{f, b, x, y, z, u, v, h, t}:
      %Equal.sym(Bool, U.Color.same(f, f), True{}, color_same_refl(f)) : {Bool.and(_, Bool.and(U.Color.same(b, b), Bool.and(U.Bool.same(x, x), Bool.and(U.Bool.same(y, y), Bool.and(U.Bool.same(z, z),
         Bool.and(U.Bool.same(u, u), Bool.and(U.Bool.same(v, v), Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))))) == True{} : Bool}
      %Equal.sym(Bool, U.Color.same(b, b), True{}, color_same_refl(b)) : {Bool.and(True{}, Bool.and(_, Bool.and(U.Bool.same(x, x), Bool.and(U.Bool.same(y, y), Bool.and(U.Bool.same(z, z),
         Bool.and(U.Bool.same(u, u), Bool.and(U.Bool.same(v, v), Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))))) == True{} : Bool}
      %Equal.sym(Bool, Bool.and(U.Bool.same(x, x), Bool.and(U.Bool.same(y, y), Bool.and(U.Bool.same(z, z),
         Bool.and(U.Bool.same(u, u), Bool.and(U.Bool.same(v, v), Bool.and(U.Bool.same(h, h), U.Bool.same(t, t))))))), True{}, mods_refl(x, y, z, u, v, h, t))
        : {Bool.and(True{}, Bool.and(True{}, _)) == True{} : Bool}
      {==}

def look_eq_refl(+k: U.Look) -> {U.Look.is_eq(k, k) == True{} : Bool}:
  match k:
    case U.Look.Of{st, link}:
      and_tt(U.Style.same(st, st), U.Str.same(link, link), style_same_refl(st), str_same_refl(link))

def cell_eq_refl(+c: U.Cell) -> {U.Cell.is_eq(c, c) == True{} : Bool}:
  match c:
    case U.Cell.Of{g, k}:
      and_tt(U.Str.same(g, g), U.Look.is_eq(k, k), str_same_refl(g), look_eq_refl(k))
    case U.Cell.Pad{}:
      {==}

def row_eq_refl(+r: List<&2, U.Cell>) -> {U.row_eq(r, r) == True{} : Bool}:
  match r:
    case Nil{}:
      {==}
    case x <> t:
      and_tt(U.Cell.is_eq(x, x), U.row_eq(t, t), cell_eq_refl(x), row_eq_refl(t))

def diff_row_self(+p: U.Pen, +n: List<&2, U.Cell>, +y: U32) -> {U.Frame.diff.row(p, n, n, y) == "" : String}:
  %Equal.sym(Bool, U.row_eq(n, n), True{}, row_eq_refl(n)) : {U.Frame.diff.row.if(p, n, y, _) == "" : String}
  {==}

# AllEmpty(xs): every string in xs is ""
def AllEmpty(xs: List<&2, String>) -> Type:
  match xs:
    case Nil{}:
      Unit
    case x <> t:
      ({x == "" : String} & AllEmpty(t))

def diff_go_self(+f: List<&2, List<&2, U.Cell>>, +p: U.Pen, +y: U32) -> AllEmpty(U.Frame.diff.go(f, f, p, y)):
  match f:
    case Nil{}:
      Unit{}
    case n <> t:
      (diff_row_self(p, n, y), diff_go_self(t, p, (y + 1 : U32)))

def concat_empty(+xs: List<&2, String>, e: AllEmpty(xs)) -> {String.concat(xs) == "" : String}:
  match xs:
    case Nil{}:
      {==}
    case h <> t:
      (eh, et) = e
      %Equal.sym(String, String.concat(t), "", concat_empty(t, et)) : {String.append(h, _) == "" : String}
      %Equal.sym(String, h, "", eh) : {String.append(_, "") == "" : String}
      {==}

def Laws.diff_self(p, f):
  concat_empty(U.Frame.diff.go(f, f, p, 1), diff_go_self(f, p, 1))

# The inline laws: a redraw starts at the first changed line, and the
# same lines have none (str_same_refl line by line); the done views
# left to write are a drop by the count already written, which is
# empty for the same list and the added views for a longer one.

def Laws.lines_first_same(ls, i):
  match ls:
    case Nil{}:
      {==}
    case h <> t:
      %Equal.sym(Bool, U.Str.same(h, h), True{}, str_same_refl(h)) : {U.Lines.first.at(_, U.Lines.first(t, t, 1n+i), i) == None{} : Maybe<&2, Nat>}
      %Equal.sym(Maybe<&2, Nat>, U.Lines.first(t, t, 1n+i), None{}, Laws.lines_first_same(t, 1n+i)) : {U.Lines.first.at(True{}, _, i) == None{} : Maybe<&2, Nat>}
      {==}

def write_same(+tty: Bool, +ls: List<&2, String>) -> {U.Inline.write(tty, ls, Nil{}, ls) == "" : String}:
  match tty:
    case True{}:
      %Equal.sym(Maybe<&2, Nat>, U.Lines.first(ls, ls, 0n), None{}, Laws.lines_first_same(ls, 0n)) : {U.Inline.sync(U.Inline.redraw(List.length(&2, String, ls), _, ls)) == "" : String}
      {==}
    case False{}:
      {==}

def drop_len(+xs: List<&2, U.View>) -> {List.drop(&2, U.View, xs, List.length(&2, U.View, xs)) == Nil{} : List<&2, U.View>}:
  match xs:
    case Nil{}:
      {==}
    case h <> t:
      drop_len(t)

def drop_zero(+ys: List<&2, U.View>) -> {List.drop(&2, U.View, ys, 0n) == ys : List<&2, U.View>}:
  match ys:
    case Nil{}:
      {==}
    case h <> t:
      {==}

def drop_len_append(+xs: List<&2, U.View>, +ys: List<&2, U.View>) -> {List.drop(&2, U.View, List.append(&2, U.View, xs, ys), List.length(&2, U.View, xs)) == ys : List<&2, U.View>}:
  match xs:
    case Nil{}:
      drop_zero(ys)
    case h <> t:
      drop_len_append(t, ys)

def Laws.inline_same(st, s):
  match st:
    case U.Inline{tty, p, w, rows, prev, printed}:
      match s:
        case U.Screen{done, live}:
          %Equal.sym(List<&2, U.View>, List.drop(&2, U.View, done, List.length(&2, U.View, done)), Nil{}, drop_len(done))
            : {U.Inline.write(tty, U.Inline.clip(rows, U.View.lines(p, live, w)), U.Views.lines(p, _, w), U.Inline.clip(rows, U.View.lines(p, live, w))) == "" : String}
          write_same(tty, U.Inline.clip(rows, U.View.lines(p, live, w)))

def Laws.static_once(st, done, more, live):
  match st:
    case U.Inline{tty, p, w, rows, prev, printed}:
      drop_len_append(done, more)

def Laws.pipe_plain(prev, fresh, next):
  {==}
