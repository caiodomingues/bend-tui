# bend-tui: the loop. Tui.run(~M, ~app, m0, ms): each turn renders the
# view of the state at the terminal's size, writes what changed
# (everything, after a resize), reads the keys within ms, and hands
# them to update, which answers the next state or None to quit; Ctrl-C
# quits too. Like App.run, the loop is a template over a closed app,
# and the helpers take the rest of the loop as a closure, called once.
#
# The loop runs bend-tty's effects, which no proof may import, so it
# lives apart from tui.bend; a program imports both.

import Base
import ../bend-tty/tty.bend as T
import ../bend-tty/tty_io.bend as IOT
import ./tui.bend as U

def Tui.quit() -> IO(Unit):
  do IO<Unit>:
    IO.write(T.Tty.cursor(True{}) ++ T.Tty.alt(False{}) ++ T.Tty.reset())
    IOT.Tty.raw(False{})

# whether the keys hold Ctrl-C (Ctrl{3})
def Tui.ctrl_c(ks: List<&2, T.Key>) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case T.Ctrl{c} <> t:
      Bool.or(U32.is_eq(c, 3), Tui.ctrl_c(t))
    case k <> t:
      Tui.ctrl_c(t)

# whether the bytes end in a lone ESC: the start of a sequence the
# rest of which may still be on its way
def Tui.split_esc(bs: List<&2, U32>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case b <> Nil{}:
      U32.is_eq(b, 27)
    case b <> t:
      Tui.split_esc(t)

def Tui.next(-M: Data, frame: List<&2, List<&2, U.Cell>>, next: Maybe<&2, M>, rest: List<&2, List<&2, U.Cell>> -> M -> IO(Unit)) -> IO(Unit):
  match next:
    case None{}:
      Tui.quit()
    case Some{m}:
      rest(frame, m)

def Tui.keys.if(-M: Data, frame: List<&2, List<&2, U.Cell>>, update: List<&2, T.Key> -> M -> Maybe<&2, M>, m: M, ks: List<&2, T.Key>, rest: List<&2, List<&2, U.Cell>> -> M -> IO(Unit), quit: Bool) -> IO(Unit):
  match quit:
    case True{}:
      Tui.quit()
    case False{}:
      Tui.next(M, frame, update(ks, m), rest)

# the keys of the turn to update, unless one is Ctrl-C
def Tui.keys(-M: Data, frame: List<&2, List<&2, U.Cell>>, update: List<&2, T.Key> -> M -> Maybe<&2, M>, m: M, +ks: List<&2, T.Key>, rest: List<&2, List<&2, U.Cell>> -> M -> IO(Unit)) -> IO(Unit):
  Tui.keys.if(M, frame, update, m, ks, rest, Tui.ctrl_c(ks))

# the bytes after a lone ESC: a short second read, appended
def Tui.more(-M: Data, frame: List<&2, List<&2, U.Cell>>, update: List<&2, T.Key> -> M -> Maybe<&2, M>, m: M, bs: List<&2, U32>, got2: Maybe<&2, List<&2, U32>>, rest: List<&2, List<&2, U.Cell>> -> M -> IO(Unit)) -> IO(Unit):
  match got2:
    case None{}:
      Tui.quit()
    case Some{bs2}:
      Tui.keys(M, frame, update, m, T.Tty.keys(List.append(&2, U32, bs, bs2)), rest)

def Tui.read.if(-M: Data, frame: List<&2, List<&2, U.Cell>>, update: List<&2, T.Key> -> M -> Maybe<&2, M>, m: M, bs: List<&2, U32>, rest: List<&2, List<&2, U.Cell>> -> M -> IO(Unit), split: Bool) -> IO(Unit):
  match split:
    case False{}:
      Tui.keys(M, frame, update, m, T.Tty.keys(bs), rest)
    case True{}:
      do IO<Unit>:
        got2 : Maybe<&2, List<&2, U32>> <- IOT.Tty.read(100, 4096)
        Tui.more(M, frame, update, m, bs, got2, rest)

def Tui.read(-M: Data, frame: List<&2, List<&2, U.Cell>>, update: List<&2, T.Key> -> M -> Maybe<&2, M>, m: M, got: Maybe<&2, List<&2, U32>>, rest: List<&2, List<&2, U.Cell>> -> M -> IO(Unit)) -> IO(Unit):
  match got:
    case None{}:
      Tui.quit()
    case Some{+bs}:
      Tui.read.if(M, frame, update, m, bs, rest, Tui.split_esc(bs))

# the frame prev to diff against: none after a resize
def Tui.prev(prev: List<&2, List<&2, U.Cell>>, same: Bool) -> List<&2, List<&2, U.Cell>>:
  match same:
    case True{}:
      prev
    case False{}:
      Nil{}

def Tui.step(-M: Data, app: U.Tui<M>, wh: U32 & U32, +lw: U32, +lh: U32, prev: List<&2, List<&2, U.Cell>>, +m: M, +ms: U32, rest: U32 -> U32 -> List<&2, List<&2, U.Cell>> -> M -> IO(Unit)) -> IO(Unit):
  U.Tui{view, update} = app
  (+w, +h) = wh
  +frame = U.render(view(m), U32.to_nat(w), U32.to_nat(h))
  do IO<Unit>:
    IO.write(U.Frame.diff(frame, Tui.prev(prev, Bool.and(U32.is_eq(w, lw), U32.is_eq(h, lh)))))
    got : Maybe<&2, List<&2, U32>> <- IOT.Tty.read(ms, 4096)
    Tui.read(M, frame, update, m, got, rest(w, h))

def Tui.loop(~M: Data, ~app: U.Tui<M>, fuel: Nat, lw: U32, lh: U32, prev: List<&2, List<&2, U.Cell>>, m: M, +ms: U32) -> IO(Unit):
  match fuel:
    case 0n:
      Tui.quit()
    case 1n+f:
      do IO<Unit>:
        wh : U32 & U32 <- IOT.Tty.size()
        Tui.step(M, app, wh, lw, lh, prev, m, ms, w2 => h2 => p2 => m2 => Tui.loop(~M, ~app, f, w2, h2, p2, m2, ms))

def Tui.run(~M: Data, ~app: U.Tui<M>, m0: M, ms: U32) -> IO(Unit):
  do IO<Unit>:
    IOT.Tty.raw(True{})
    IO.write(T.Tty.alt(True{}) ++ T.Tty.cursor(False{}) ++ T.Tty.clear())
    Tui.loop(~M, ~app, U32.to_nat(4294967295), 0, 0, Nil{}, m0, ms)
