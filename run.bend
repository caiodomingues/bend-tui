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
import ../bend-tty/color.bend as C
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

def Tui.step(-M: Data, app: U.Tui<M>, +pen: U.Pen, wh: U32 & U32, +lw: U32, +lh: U32, prev: List<&2, List<&2, U.Cell>>, +m: M, +ms: U32, rest: U32 -> U32 -> List<&2, List<&2, U.Cell>> -> M -> IO(Unit)) -> IO(Unit):
  U.Tui{view, update} = app
  (+w, +h) = wh
  +frame = U.render(view(m), U32.to_nat(w), U32.to_nat(h))
  do IO<Unit>:
    IO.write(U.Frame.diff(pen, frame, Tui.prev(prev, Bool.and(U32.is_eq(w, lw), U32.is_eq(h, lh)))))
    got : Maybe<&2, List<&2, U32>> <- IOT.Tty.read(ms, 4096)
    Tui.read(M, frame, update, m, got, rest(w, h))

def Tui.loop(~M: Data, ~app: U.Tui<M>, fuel: Nat, +pen: U.Pen, lw: U32, lh: U32, prev: List<&2, List<&2, U.Cell>>, m: M, +ms: U32) -> IO(Unit):
  match fuel:
    case 0n:
      Tui.quit()
    case 1n+f:
      do IO<Unit>:
        wh : U32 & U32 <- IOT.Tty.size()
        Tui.step(M, app, pen, wh, lw, lh, prev, m, ms, w2 => h2 => p2 => m2 => Tui.loop(~M, ~app, f, pen, w2, h2, p2, m2, ms))

def Tui.run(~M: Data, ~app: U.Tui<M>, m0: M, ms: U32) -> IO(Unit):
  do IO<Unit>:
    IOT.Tty.raw(True{})
    IO.write(T.Tty.alt(True{}) ++ T.Tty.cursor(False{}) ++ T.Tty.clear())
    l : C.Level <- IOT.Tty.level(1)
    Tui.loop(~M, ~app, U32.to_nat(4294967295), U.Pen{l, True{}}, 0, 0, Nil{}, m0, ms)

# The CLI loop
# ------------
# Cli.run(~M, ~Msg, ~app, m0, work, tick) draws inline, in the normal
# screen, and answers the last state. work runs as its own computation
# and posts messages (Cli.post); each turn takes one event, the next
# message, or the keys while app.keys(m) holds (raw mode on only then),
# or a tick when nothing came within tick ms, and hands it to update.
# Ctrl-C is Ev.Cancel, and the loop stops after it whatever update
# answers. The output is a live terminal when stdout is one, TERM is
# not dumb and CI is unset; otherwise nothing moves the cursor.

def Cli.post(-Msg: Data, ch: Chan(U.Ev<Msg>), m: Msg) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U.Ev<Msg>, Unit> <- Chan.send(U.Ev<Msg>, ch, U.Ev.Msg{m})
    IO.pure(Unit, Unit{})

def Cli.work(-Msg: Data, +ch: Chan(U.Ev<Msg>), work: Chan(U.Ev<Msg>) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    work(ch)
    r : Result<&1, &1, U.Ev<Msg>, Unit> <- Chan.send(U.Ev<Msg>, ch, U.Ev.Done{})
    IO.pure(Unit, Unit{})

# no work: for a loop that only asks
def Cli.none(-Msg: Data, ch: Chan(U.Ev<Msg>)) -> IO(Unit):
  IO.pure(Unit, Unit{})

def Cli.is(r: Result<&1, &1, U32 & String, String>, +v: String) -> Bool:
  match r:
    case Done{x}:
      String.eq(x, v)
    case Fail{e}:
      False{}

# CI set to anything but "", "0" or "false"
def Cli.ci(r: Result<&1, &1, U32 & String, String>) -> Bool:
  match r:
    case Done{+x}:
      Bool.not(Bool.or(String.eq(x, ""), Bool.or(String.eq(x, "0"), String.eq(x, "false"))))
    case Fail{e}:
      False{}

def Cli.live(tty: Bool, term: Result<&1, &1, U32 & String, String>, ci: Result<&1, &1, U32 & String, String>) -> Bool:
  Bool.and(tty, Bool.and(Bool.not(Cli.is(term, "dumb")), Bool.not(Cli.ci(ci))))

def Cli.found(-Msg: Data, r: Maybe<&1, U.Ev<Msg>>) -> U.Ev<Msg>:
  match r:
    case Some{e}:
      e
    case None{}:
      U.Ev.Tick{}

def Cli.polled(-Msg: Data, p: Poll<&1, &1, Maybe<&1, U.Ev<Msg>>, Unit>) -> U.Ev<Msg>:
  match p:
    case Ready{r}:
      Cli.found(Msg, r)
    case Wait{u}:
      U.Ev.Tick{}

def Cli.keys.if(-Msg: Data, +ks: List<&2, T.Key>, stop: Bool) -> U.Ev<Msg>:
  match stop:
    case True{}:
      U.Ev.Cancel{}
    case False{}:
      U.Ev.Keys{ks}

def Cli.keys(-Msg: Data, bs: List<&2, U32>) -> U.Ev<Msg>:
  +ks = T.Tty.keys(bs)
  Cli.keys.if(Msg, ks, Tui.ctrl_c(ks))

def Cli.more(-Msg: Data, bs: List<&2, U32>, got2: Maybe<&2, List<&2, U32>>) -> U.Ev<Msg>:
  match got2:
    case None{}:
      U.Ev.Cancel{}
    case Some{bs2}:
      Cli.keys(Msg, List.append(&2, U32, bs, bs2))

def Cli.split(-Msg: Data, bs: List<&2, U32>, split: Bool) -> IO(U.Ev<Msg>):
  match split:
    case False{}:
      IO.pure(U.Ev<Msg>, Cli.keys(Msg, bs))
    case True{}:
      do IO<U.Ev<Msg>>:
        got2 : Maybe<&2, List<&2, U32>> <- IOT.Tty.read(100, 4096)
        return Cli.more(Msg, bs, got2)

def Cli.empty(bs: List<&2, U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case b <> t:
      False{}

def Cli.bytes(-Msg: Data, +bs: List<&2, U32>, none: Bool) -> IO(U.Ev<Msg>):
  match none:
    case True{}:
      IO.pure(U.Ev<Msg>, U.Ev.Tick{})
    case False{}:
      Cli.split(Msg, bs, Tui.split_esc(bs))

# a read's answer: the end of the input cancels, nothing is a tick
def Cli.got(-Msg: Data, got: Maybe<&2, List<&2, U32>>) -> IO(U.Ev<Msg>):
  match got:
    case None{}:
      IO.pure(U.Ev<Msg>, U.Ev.Cancel{})
    case Some{+bs}:
      Cli.bytes(Msg, bs, Cli.empty(bs))

def Cli.read(-Msg: Data, +tick: U32) -> IO(U.Ev<Msg>):
  do IO<U.Ev<Msg>>:
    got : Maybe<&2, List<&2, U32>> <- IOT.Tty.read(tick, 4096)
    Cli.got(Msg, got)

def Cli.waiting(-Msg: Data, r: Maybe<&1, U.Ev<Msg>>, +tick: U32) -> IO(U.Ev<Msg>):
  match r:
    case Some{e}:
      IO.pure(U.Ev<Msg>, e)
    case None{}:
      Cli.read(Msg, tick)

# a message already waiting goes first; else the keys of one read
def Cli.keys_or(-Msg: Data, p: Poll<&1, &1, Maybe<&1, U.Ev<Msg>>, Unit>, +tick: U32) -> IO(U.Ev<Msg>):
  match p:
    case Ready{r}:
      Cli.waiting(Msg, r, tick)
    case Wait{u}:
      Cli.read(Msg, tick)

def Cli.event(-Msg: Data, +ch: Chan(U.Ev<Msg>), want: Bool, +tick: U32) -> IO(U.Ev<Msg>):
  match want:
    case False{}:
      do IO<U.Ev<Msg>>:
        p : Poll<&1, &1, Maybe<&1, U.Ev<Msg>>, Unit> <- Chan.try_recv(U.Ev<Msg>, ch, tick)
        return Cli.polled(Msg, p)
    case True{}:
      do IO<U.Ev<Msg>>:
        p : Poll<&1, &1, Maybe<&1, U.Ev<Msg>>, Unit> <- Chan.try_recv(U.Ev<Msg>, ch, 0)
        Cli.keys_or(Msg, p, tick)

def Cli.hide(live: Bool) -> String:
  match live:
    case True{}:
      T.Tty.cursor(False{})
    case False{}:
      ""

def Cli.show(live: Bool) -> String:
  match live:
    case True{}:
      T.Tty.cursor(True{})
    case False{}:
      ""

# raw mode as the view wants it; leaving raw mode shows the cursor, so
# a live output hides it again
def Cli.mode(raw: Bool, want: Bool, live: Bool) -> IO(Unit):
  match raw want:
    case False{} True{}:
      IOT.Tty.raw(True{})
    case True{} False{}:
      do IO<Unit>:
        IOT.Tty.raw(False{})
        IO.write(Cli.hide(live))
    case r w:
      IO.pure(Unit, Unit{})

def Cli.inline(live: Bool, on: Bool) -> IO(Unit):
  match live:
    case True{}:
      IOT.Tty.inline(on)
    case False{}:
      IO.pure(Unit, Unit{})

def Cli.unraw(raw: Bool) -> IO(Unit):
  match raw:
    case True{}:
      IOT.Tty.raw(False{})
    case False{}:
      IO.pure(Unit, Unit{})

def Cli.is_cancel(-Msg: Data, e: U.Ev<Msg>) -> Bool:
  match e:
    case U.Ev.Cancel{}:
      True{}
    case other:
      False{}

def Cli.live_of(st: U.Inline) -> Bool:
  match st:
    case U.Inline{tty, p, w, rows, prev, printed, up, cur}:
      tty

# the last frame written whole, the cursor shown, raw mode off
def Cli.end(-M: Data, -Msg: Data, app: U.Cli<M, Msg>, +st: U.Inline, +m: M, raw: Bool) -> IO(M):
  U.Cli{view, update, keys} = app
  do IO<M>:
    IO.write(U.Inline.end(st, view(m)) ++ Cli.show(Cli.live_of(st)))
    Cli.unraw(raw)
    Cli.inline(Cli.live_of(st), False{})
    return m

def Cli.after.go(-M: Data, m: M, st: U.Inline, raw: Bool, stop: Bool,
                 go: U.Inline -> M -> Bool -> IO(M), fin: U.Inline -> M -> Bool -> IO(M)) -> IO(M):
  match stop:
    case True{}:
      fin(st, m, raw)
    case False{}:
      go(st, m, raw)

def Cli.after(-M: Data, s: U.Step<M>, st: U.Inline, raw: Bool, stop: Bool,
              go: U.Inline -> M -> Bool -> IO(M), fin: U.Inline -> M -> Bool -> IO(M)) -> IO(M):
  match s:
    case U.Step.Go{m}:
      Cli.after.go(M, m, st, raw, stop, go, fin)
    case U.Step.End{m}:
      fin(st, m, raw)

def Cli.step(-M: Data, -Msg: Data, app: U.Cli<M, Msg>, +ch: Chan(U.Ev<Msg>), +st: U.Inline, wh: U32 & U32, +m: M, raw: Bool, +tick: U32,
             go: U.Inline -> M -> Bool -> IO(M), fin: U.Inline -> M -> Bool -> IO(M)) -> IO(M):
  U.Cli{view, update, keys} = app
  (+w, +h) = wh
  +want = keys(m)
  +live = Cli.live_of(st)
  +o1 = U.Inline.resize(st, U32.to_nat(w), U32.to_nat(h))
  +o2 = U.Inline.draw(U.Inline.next(o1), view(m))
  do IO<M>:
    IO.write(U.Inline.text(o1) ++ U.Inline.text(o2))
    Cli.mode(raw, want, live)
    +ev : U.Ev<Msg> <- Cli.event(Msg, ch, want, tick)
    Cli.after(M, update(ev, m), U.Inline.next(o2), want, Cli.is_cancel(Msg, ev), go, fin)

def Cli.loop(~M: Data, ~Msg: Data, ~app: U.Cli<M, Msg>, fuel: Nat, +ch: Chan(U.Ev<Msg>), st: U.Inline, m: M, raw: Bool, +tick: U32) -> IO(M):
  match fuel:
    case 0n:
      Cli.end(M, Msg, app, st, m, raw)
    case 1n+f:
      do IO<M>:
        wh : U32 & U32 <- IOT.Tty.size()
        Cli.step(M, Msg, app, ch, st, wh, m, raw, tick,
          s2 => m2 => r2 => Cli.loop(~M, ~Msg, ~app, f, ch, s2, m2, r2, tick),
          s2 => m2 => r2 => Cli.end(M, Msg, app, s2, m2, r2))

def Cli.start(~M: Data, ~Msg: Data, ~app: U.Cli<M, Msg>, +live: Bool, l: C.Level, wh: U32 & U32, +ch: Chan(U.Ev<Msg>), m0: M, +tick: U32) -> IO(M):
  (w, h) = wh
  do IO<M>:
    Cli.inline(live, True{})
    IO.write(Cli.hide(live))
    Cli.loop(~M, ~Msg, ~app, U32.to_nat(4294967295), ch, U.Inline.new(live, U.Pen{l, live}, U32.to_nat(w), U32.to_nat(h)), m0, False{}, tick)

def Cli.run(~M: Data, ~Msg: Data, ~app: U.Cli<M, Msg>, m0: M, work: Chan(U.Ev<Msg>) -> IO(Unit), tick: U32) -> IO(M):
  do IO<M>:
    tty : Bool <- IOT.Tty.isatty(1)
    term : Result<&1, &1, U32 & String, String> <- IO.get_env("TERM")
    ci : Result<&1, &1, U32 & String, String> <- IO.get_env("CI")
    l : C.Level <- IOT.Tty.level(1)
    wh : U32 & U32 <- IOT.Tty.size()
    +ch : Chan(U.Ev<Msg>) <- Chan.new(U.Ev<Msg>, 64)
    IO.spawn(Unit, Cli.work(Msg, ch, work))
    Cli.start(~M, ~Msg, ~app, Cli.live(tty, term, ci), l, wh, ch, m0, tick)

# Prompts
# -------
# One call a question, as @clack/prompts asks: a Cli.run with no work,
# raw mode on while the question is open, its answer as it ends. The
# answered prompt stays in the scrollback as its title and answer.
# None when Esc, Ctrl-C or the end of the input cancels it.

def Prompt.none(ch: Chan(U.Ev<Unit>)) -> IO(Unit):
  IO.pure(Unit, Unit{})

def Prompt.go(-P: Data, +p: P, open: Bool) -> U.Step<P>:
  match open:
    case True{}:
      U.Step.Go{p}
    case False{}:
      U.Step.End{p}

def Pick.screen(p: U.Pick) -> U.Screen:
  U.Screen{Nil{}, U.Pick.view(p)}

def Pick.update(e: U.Ev<Unit>, p: U.Pick) -> U.Step<U.Pick>:
  match e:
    case U.Ev.Keys{ks}:
      +q = U.Pick.keys(ks, p)
      Prompt.go(U.Pick, q, U.Pick.open(q))
    case U.Ev.Cancel{}:
      U.Step.End{U.Pick.cancel(p)}
    case other:
      U.Step.Go{p}

def Yes.screen(p: U.Yes) -> U.Screen:
  U.Screen{Nil{}, U.Yes.view(p)}

def Yes.update(e: U.Ev<Unit>, p: U.Yes) -> U.Step<U.Yes>:
  match e:
    case U.Ev.Keys{ks}:
      +q = U.Yes.keys(ks, p)
      Prompt.go(U.Yes, q, U.Yes.open(q))
    case U.Ev.Cancel{}:
      U.Step.End{U.Yes.cancel(p)}
    case other:
      U.Step.Go{p}

def Field.screen(p: U.Field) -> U.Screen:
  U.Screen{Nil{}, U.Field.view(p)}

def Field.update(e: U.Ev<Unit>, p: U.Field) -> U.Step<U.Field>:
  match e:
    case U.Ev.Keys{ks}:
      +q = U.Field.keys(ks, p)
      Prompt.go(U.Field, q, U.Field.open(q))
    case U.Ev.Cancel{}:
      U.Step.End{U.Field.cancel(p)}
    case other:
      U.Step.Go{p}

# one of the items; None when cancelled
def Prompt.select(title: String, items: List<&2, String>) -> IO(Maybe<&2, Nat>):
  do IO<Maybe<&2, Nat>>:
    p : U.Pick <- Cli.run(~U.Pick, ~Unit, ~U.Cli{Pick.screen, Pick.update, U.Pick.open}, U.Pick.new(title, items, False{}), Prompt.none, 80)
    return U.Pick.answer(p)

# the items marked with Space; None when cancelled
def Prompt.multi(title: String, items: List<&2, String>) -> IO(Maybe<&2, List<&2, Nat>>):
  do IO<Maybe<&2, List<&2, Nat>>>:
    p : U.Pick <- Cli.run(~U.Pick, ~Unit, ~U.Cli{Pick.screen, Pick.update, U.Pick.open}, U.Pick.new(title, items, True{}), Prompt.none, 80)
    return U.Pick.answers(p)

# yes or no, starting at dflt; y and n answer at once
def Prompt.confirm(title: String, dflt: Bool) -> IO(Maybe<&2, Bool>):
  do IO<Maybe<&2, Bool>>:
    p : U.Yes <- Cli.run(~U.Yes, ~Unit, ~U.Cli{Yes.screen, Yes.update, U.Yes.open}, U.Yes{title, dflt, U.Ask.Open{}}, Prompt.none, 80)
    return U.Yes.answer(p)

# a line of text, the placeholder when nothing is typed
def Prompt.text(title: String, placeholder: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    p : U.Field <- Cli.run(~U.Field, ~Unit, ~U.Cli{Field.screen, Field.update, U.Field.open}, U.Field.new(title, placeholder), Prompt.none, 80)
    return U.Field.answer(p)
