# bend-tui: the proofs. fit and fit_rows recurse on the size, so each
# count is one induction on it; render is fit_rows of draw, so its
# laws are the fit_rows laws applied to whatever draw gives.

import Base
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
# comparisons, from U32.cmp up), so every row's diff is "", and a join
# of empty strings is empty. AllEmpty carries the second fact.


def u32_eq_refl(+x: U32) -> {U32.is_eq(x, x) == True{} : Bool}:
  %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, S.u32_cmp_refl(x)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

def bool_same_refl(+b: Bool) -> {U.Bool.same(b, b) == True{} : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def style_eq_refl(+s: U.Style) -> {U.Style.is_eq(s, s) == True{} : Bool}:
  match s:
    case U.Style{f, b, o}:
      %Equal.sym(Bool, U32.is_eq(f, f), True{}, u32_eq_refl(f)) : {Bool.and(_, Bool.and(U32.is_eq(b, b), U.Bool.same(o, o))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(b, b), True{}, u32_eq_refl(b)) : {Bool.and(True{}, Bool.and(_, U.Bool.same(o, o))) == True{} : Bool}
      %Equal.sym(Bool, U.Bool.same(o, o), True{}, bool_same_refl(o)) : {Bool.and(True{}, Bool.and(True{}, _)) == True{} : Bool}
      {==}

def cell_eq_refl(+c: U.Cell) -> {U.Cell.is_eq(c, c) == True{} : Bool}:
  match c:
    case U.Cell{ch, st}:
      %Equal.sym(Bool, U32.is_eq(ch, ch), True{}, u32_eq_refl(ch)) : {Bool.and(_, U.Style.is_eq(st, st)) == True{} : Bool}
      %Equal.sym(Bool, U.Style.is_eq(st, st), True{}, style_eq_refl(st)) : {Bool.and(True{}, _) == True{} : Bool}
      {==}

def row_eq_refl(+r: List<&2, U.Cell>) -> {U.row_eq(r, r) == True{} : Bool}:
  match r:
    case Nil{}:
      {==}
    case x <> t:
      %Equal.sym(Bool, U.Cell.is_eq(x, x), True{}, cell_eq_refl(x)) : {Bool.and(_, U.row_eq(t, t)) == True{} : Bool}
      %Equal.sym(Bool, U.row_eq(t, t), True{}, row_eq_refl(t)) : {Bool.and(True{}, _) == True{} : Bool}
      {==}

def diff_row_self(+n: List<&2, U.Cell>, +y: U32) -> {U.Frame.diff.row(n, n, y) == "" : String}:
  %Equal.sym(Bool, U.row_eq(n, n), True{}, row_eq_refl(n)) : {U.Frame.diff.row.if(n, y, _) == "" : String}
  {==}

# AllEmpty(xs): every string in xs is ""
def AllEmpty(xs: List<&2, String>) -> Type:
  match xs:
    case Nil{}:
      Unit
    case x <> t:
      ({x == "" : String} & AllEmpty(t))

def diff_go_self(+f: List<&2, List<&2, U.Cell>>, +y: U32) -> AllEmpty(U.Frame.diff.go(f, f, y)):
  match f:
    case Nil{}:
      Unit{}
    case n <> t:
      (diff_row_self(n, y), diff_go_self(t, (y + 1 : U32)))

def join_go_empty(+t: List<&2, String>, +h: String, eh: {h == "" : String}, et: AllEmpty(t)) -> {String.join.go(t, h, "") == "" : String}:
  match t:
    case Nil{}:
      %eh : {h == _ : String}
      {==}
    case h2 <> t2:
      (e2, rest) = et
      %Equal.sym(String, String.join.go(t2, h2, ""), "", join_go_empty(t2, h2, e2, rest)) : {String.append(h, String.append("", _)) == "" : String}
      %Equal.sym(String, h, "", eh) : {String.append(_, "") == "" : String}
      {==}

def join_empty(+xs: List<&2, String>, e: AllEmpty(xs)) -> {String.join(xs, "") == "" : String}:
  match xs:
    case Nil{}:
      {==}
    case h <> t:
      (eh, et) = e
      join_go_empty(t, h, eh, et)

def Laws.diff_self(f):
  join_empty(U.Frame.diff.go(f, f, 1), diff_go_self(f, 1))
