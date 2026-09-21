# life: Conway's Game of Life on a 60x16 grid, a generation per tick,
# every row in its own color, red at the top through green and blue to
# magenta at the bottom. Space pauses, r reseeds, Esc quits.
#
#   bend demos/life.bend -o life && ./life
import Base
import ../../bend-tty/tty.bend as T
import ../tui.bend as U

def W() -> Nat:
  60n

def H() -> Nat:
  16n

# rows of cells, alive or not; seed is the stream r draws the next grid from
type Life is Data:
  Life{rows: List<&2, List<&2, Bool>>, gen: Nat, run: Bool, seed: U32}

# Seeding
# -------

# xorshift32: the word after x in its stream
def xorshift(+x: U32) -> U32:
  +a = (x .^. (x << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

# whether cell i of the grid seeded by seed starts alive: a hash of the
# two, alive two times in five
def seeded(+seed: U32, i: U32) -> Bool:
  +h = xorshift(xorshift(U32.xor(seed, U32.mul(U32.add(i, 1), 2654435761))))
  U32.is_lt(U32.mod((h >> 8n : U32), 5), 2)

def seed_row(w: Nat, +i: U32, +seed: U32) -> List<&2, Bool>:
  match w:
    case 0n:
      Nil{}
    case 1n+p:
      seeded(seed, i) <> seed_row(p, U32.add(i, 1), seed)

def seed_rows(h: Nat, +i: U32, +seed: U32) -> List<&2, List<&2, Bool>>:
  match h:
    case 0n:
      Nil{}
    case 1n+p:
      seed_row(W(), i, seed) <> seed_rows(p, U32.add(i, U32.from_nat(W())), seed)

def seed_grid(+seed: U32) -> Life:
  Life{seed_rows(H(), 0, seed), 0n, True{}, seed}

# Generations
# -----------

def bit(b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

# each cell summed with its left and right neighbors: a row's part of
# every 3x3 count; a and b are the two cells before rest
def tri.go(rest: List<&2, Bool>, +a: U32, +b: U32) -> List<&2, U32>:
  match rest:
    case Nil{}:
      [U32.add(a, b)]
    case x <> t:
      +c = bit(x)
      U32.add(U32.add(a, b), c) <> tri.go(t, b, c)

def tri(r: List<&2, Bool>) -> List<&2, U32>:
  match r:
    case Nil{}:
      Nil{}
    case x <> t:
      tri.go(t, 0, bit(x))

# the tri of the first row, or nothing: the grid ends
def tri_head(rows: List<&2, List<&2, Bool>>) -> List<&2, U32>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      tri(r)

# two rows of counts summed cell by cell; a missing row counts nothing
def zipadd(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  match xs ys:
    case Nil{} b:
      b
    case a Nil{}:
      a
    case x <> xt y <> yt:
      U32.add(x, y) <> zipadd(xt, yt)

# a cell's fate from the count of its 3x3 block, itself included: at 3
# it lives or is born, at 4 it lives if it was alive
def fate(+n: U32, alive: Bool) -> Bool:
  U32.is_eq(n, 3) || (U32.is_eq(n, 4) && alive)

def fates(ns: List<&2, U32>, cells: List<&2, Bool>) -> List<&2, Bool>:
  match ns cells:
    case n <> nt x <> xt:
      fate(n, x) <> fates(nt, xt)
    case a b:
      Nil{}

# every row's next generation; above is the tri of the row before it
def evolve.go(+rows: List<&2, List<&2, Bool>>, above: List<&2, U32>) -> List<&2, List<&2, Bool>>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> t:
      +tc = tri(r)
      fates(zipadd(zipadd(above, tc), tri_head(t)), r) <> evolve.go(t, tc)

def evolve(rows: List<&2, List<&2, Bool>>) -> List<&2, List<&2, Bool>>:
  evolve.go(rows, Nil{})

def alive_row(cells: List<&2, Bool>) -> U32:
  match cells:
    case Nil{}:
      0
    case x <> t:
      U32.add(bit(x), alive_row(t))

def alive(rows: List<&2, List<&2, Bool>>) -> U32:
  match rows:
    case Nil{}:
      0
    case r <> t:
      U32.add(alive_row(r), alive(t))

# Update
# ------

def tick.if(rows: List<&2, List<&2, Bool>>, gen: Nat, seed: U32, run: Bool) -> Life:
  match run:
    case True{}:
      Life{evolve(rows), 1n+gen, True{}, seed}
    case False{}:
      Life{rows, gen, False{}, seed}

# a tick: one generation, unless paused
def tick(m: Life) -> Life:
  match m:
    case Life{rows, gen, run, seed}:
      tick.if(rows, gen, seed, run)

def step.at(+m: Life, k: T.Key) -> Maybe<&2, Life>:
  match m k:
    case m2 T.Esc{}:
      None{}
    case Life{rows, gen, run, seed} T.Char{32}:
      Some{Life{rows, gen, Bool.not(run), seed}}
    case Life{rows, gen, run, seed} T.Char{114}:
      Some{seed_grid(xorshift(seed))}
    case m2 other:
      Some{m2}

def step(m: Life, k: T.Key) -> Maybe<&2, Life>:
  step.at(m, k)

def update(ks: List<&2, T.Key>, m: Life) -> Maybe<&2, Life>:
  U.Tui.fold(~Life, ~step, ks, Some{tick(m)})

# View
# ----

# a row as text: a block for a live cell
def row_text(cells: List<&2, Bool>) -> String:
  match cells:
    case Nil{}:
      ""
    case x <> t:
      SCon{Chr{Bool.pick(U32, x, 9608, 32)}, row_text(t)}

def color.of(c: Maybe<&2, U32>) -> U32:
  match c:
    case Some{c}:
      c
    case None{}:
      245

# the 256-color code of row y: red, orange, yellow, green, cyan, blue,
# violet, magenta, one step per row
def color(y: Nat) -> U32:
  color.of(List.get(&2, U32, [196, 202, 208, 214, 220, 226, 190, 118, 46, 48, 50, 39, 33, 63, 129, 201], y))

# the rows stacked, each in the color of its y; blank below the last
def grid(rows: List<&2, List<&2, Bool>>, +y: Nat) -> U.View:
  match rows:
    case Nil{}:
      U.Fill{U.Cell.blank()}
    case r <> t:
      U.Above{U.Text{U.Style.fg(color(y)), row_text(r)}, grid(t, 1n+y), 1n}

def status(rows: List<&2, List<&2, Bool>>, gen: Nat, run: Bool) -> String:
  "gen " ++ Nat.show(gen) ++ "  alive " ++ U32.show(alive(rows)) ++ Bool.pick(String, run, "", "  paused") ++ "   Space pauses, r reseeds, Esc quits"

def view.at(+m: Life) -> U.View:
  match m:
    case Life{rows, gen, run, seed}:
      U.Boxed{"life", U.Below{grid(rows, 0n), U.Text{U.Style.fg(245), status(rows, gen, run)}, 1n}}

def view(m: Life) -> U.View:
  view.at(m)

def main() -> IO(Unit):
  U.Tui.run(~Life, ~U.Tui{view, update}, seed_grid(2463534242), 100)
