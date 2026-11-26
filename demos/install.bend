# install: what `ogw install` will look like. The header and each step
# done are printed once, above a live line: a spinner, then a bar while
# something has a size. At the end a summary takes the live line's place
# and stays. Piped, with TERM=dumb or with CI set, only the printed lines
# and the summary come out, with no cursor movement; NO_COLOR drops the
# colours.
#
#   bend demos/install.bend
#   bend demos/install.bend | cat

import Base
import ../../bend-tty/tty.bend as T
import ../../bend-tty/color.bend as C
import ../tui.bend as U
import ../run.bend as R

type Phase is Data:
  Phase.Resolve{}
  Phase.Fetch{}
  Phase.Verify{}
  Phase.Over{}

type St is Data:
  St{log: List<&2, U.View>, phase: Phase, got: Nat, total: Nat, tick: Nat}

type Msg is Data:
  Msg.Log{v: U.View}
  Msg.Phase{p: Phase, total: Nat}
  Msg.Got{n: Nat}

def cyan() -> C.Style:
  U.Style.color(C.Color.cyan())

def gray() -> C.Style:
  U.Style.color(C.Color.gray())

# a mark, then text that wraps under itself
def marked(mark: U.Span, rest: List<&2, U.Span>) -> U.View:
  U.Row.of([U.Flex.of(U.spans([mark, U.Span.S{" "}])), U.Flex.grow(U.spans(rest))])

def ok(rest: List<&2, U.Span>) -> U.View:
  marked(U.Span.of(U.Style.color(C.Color.green()), "✓"), rest)

def header() -> U.View:
  marked(U.Span.of(cyan(), "◇"), [U.Span.of(C.Style.bold(C.Style.plain()), "ogw install "), U.Span.of(cyan(), "0.4.0")])

# tenths shown as 41.2
def tenths(+n: Nat) -> String:
  Nat.show(Nat.div(n, 10n)) ++ "." ++ Nat.show(Nat.mod(n, 10n))

def spin(+tick: Nat) -> U.Span:
  U.Span.of(cyan(), U.Spinner.clack(tick) ++ " ")

def live(p: Phase, +got: Nat, +total: Nat, +tick: Nat) -> U.View:
  match p:
    case Phase.Resolve{}:
      U.spans([spin(tick), U.Span.S{"resolving 0.4.0"}])
    case Phase.Fetch{}:
      U.Bar.view([spin(tick), U.Span.S{"downloading "}], got, total, 20n, tenths(got) ++ " / " ++ tenths(total) ++ " MB")
    case Phase.Verify{}:
      U.Bar.view([spin(tick), U.Span.S{"verifying sha256 "}], got, total, 20n, "")
    case Phase.Over{}:
      marked(U.Span.of(gray(), "└"), [U.Span.S{"installed in "}, U.Span.of(cyan(), "~/.ogw/versions/0.4.0")])

def view(s: St) -> U.Screen:
  match s:
    case St{log, p, got, total, tick}:
      U.Screen{log, live(p, got, total, tick)}

def St.msg(s: St, m: Msg) -> St:
  match s:
    case St{log, p, got, total, tick}:
      match m:
        case Msg.Log{v}:
          St{List.append(&2, U.View, log, [v]), p, got, total, tick}
        case Msg.Phase{p2, t2}:
          St{log, p2, 0n, t2, tick}
        case Msg.Got{n}:
          St{log, p, n, total, tick}

def St.tick(s: St) -> St:
  match s:
    case St{log, p, got, total, tick}:
      St{log, p, got, total, 1n+tick}

def St.over(s: St) -> St:
  match s:
    case St{log, p, got, total, tick}:
      St{log, Phase.Over{}, got, total, tick}

def update(e: U.Ev<Msg>, s: St) -> U.Step<St>:
  match e:
    case U.Ev.Msg{m}:
      U.Step.Go{St.msg(s, m)}
    case U.Ev.Tick{}:
      U.Step.Go{St.tick(s)}
    case U.Ev.Done{}:
      U.Step.End{St.over(s)}
    case U.Ev.Cancel{}:
      U.Step.End{s}
    case U.Ev.Keys{ks}:
      U.Step.Go{s}

def no_keys(s: St) -> Bool:
  False{}

def post(+ch: Chan(U.Ev<Msg>), m: Msg) -> IO(Unit):
  R.Cli.post(Msg, ch, m)

# n steps of size step, a pause of ms before each
def steps(n: Nat, +ch: Chan(U.Ev<Msg>), +k: Nat, +step: Nat, +ms: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.sleep(ms)
        post(ch, Msg.Got{Nat.mul(k, step)})
        steps(p, ch, 1n+k, step, ms)

def elapsed(+t0: Nat, +t1: Nat) -> String:
  tenths(Nat.div(Nat.sub(t1, t0), 100n)) ++ " s"

def fetched(+ch: Chan(U.Ev<Msg>), +t0: Nat, +t1: Nat) -> IO(Unit):
  do IO<Unit>:
    post(ch, Msg.Log{ok([U.Span.S{"downloaded 41.2 MB "}, U.Span.of(gray(), "in " ++ elapsed(t0, t1))])})
    post(ch, Msg.Phase{Phase.Verify{}, 100n})
    steps(20n, ch, 1n, 5n, 70)
    post(ch, Msg.Log{ok([U.Span.S{"verified sha256 "}, U.Span.of(gray(), "9f2c1e7b…4a0d")])})

def work(c: Chan(U.Ev<Msg>)) -> IO(Unit):
  +ch = c
  do IO<Unit>:
    IO.sleep(700)
    post(ch, Msg.Log{ok([U.Span.S{"resolved 0.4.0 "}, U.Span.of(gray(), "(engine 0.4.0, Bend 2.0.40, Bun 1.4.5)")])})
    post(ch, Msg.Phase{Phase.Fetch{}, 412n})
    +t0 : Nat <- IO.now()
    steps(30n, ch, 1n, 14n, 100)
    +t1 : Nat <- IO.now()
    fetched(ch, t0, t1)

def main() -> IO(Unit):
  do IO<Unit>:
    s : St <- R.Cli.run(~St, ~Msg, ~U.Cli{view, update, no_keys}, St{[header()], Phase.Resolve{}, 0n, 0n, 0n}, work, 80)
    IO.pure(Unit, Unit{})
