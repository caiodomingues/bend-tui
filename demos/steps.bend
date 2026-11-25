# steps: Cli.run with work that posts lines and progress. The lines
# above the live one are printed once; the live line is a spinner and
# a bar, redrawn in place; at the end a summary replaces it and stays.
# Piped, or with TERM=dumb or CI=1, only the lines and the summary are
# written, with no cursor movement.
#
#   bend demos/steps.bend
#   bend demos/steps.bend | cat

import Base
import ../../bend-tty/tty.bend as T
import ../../bend-tty/color.bend as C
import ../tui.bend as U
import ../run.bend as R

type St is Data:
  St{log: List<&2, U.View>, got: Nat, tick: Nat, over: Bool}

type Msg is Data:
  Msg.Line{s: String}
  Msg.Got{n: Nat}

def green() -> C.Style:
  C.Style.fg(C.Color.green(), C.Style.plain())

def gray() -> C.Style:
  C.Style.fg(C.Color.gray(), C.Style.plain())

# a line with a coloured mark before it
def marked(+st: C.Style, mark: String, s: String) -> U.View:
  U.Beside{U.View.Text{st, mark}, U.View.Text{U.Style.plain(), s}, 2n}

def frame(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}:
      s
    case None{}:
      ""

def spin(+tick: Nat) -> String:
  frame(List.get(&2, String, ["◒", "◐", "◓", "◑"], Nat.mod(tick, 4n)))

def live(+got: Nat, +tick: Nat, over: Bool) -> U.View:
  match over:
    case True{}:
      marked(gray(), "└", "installed in ~/.ogw/versions/0.4.0")
    case False{}:
      U.Beside{marked(C.Style.fg(C.Color.magenta(), C.Style.plain()), spin(tick), "verifying sha256 "),
        U.Beside{U.Progress{got, 100n, U.Style.plain()}, U.View.Text{U.Style.plain(), " " ++ Nat.show(got) ++ "%"}, 20n}, 19n}

def view(s: St) -> U.Screen:
  match s:
    case St{log, +got, +tick, over}:
      U.Screen{log, live(got, tick, over)}

def St.line(s: St, t: String) -> St:
  match s:
    case St{log, got, tick, over}:
      St{List.append(&2, U.View, log, [marked(green(), "✓", t)]), got, tick, over}

def St.got(s: St, n: Nat) -> St:
  match s:
    case St{log, got, tick, over}:
      St{log, n, tick, over}

def St.tick(s: St) -> St:
  match s:
    case St{log, got, tick, over}:
      St{log, got, 1n+tick, over}

def St.over(s: St) -> St:
  match s:
    case St{log, got, tick, over}:
      St{log, got, tick, True{}}

def update(e: U.Ev<Msg>, s: St) -> U.Step<St>:
  match e:
    case U.Ev.Msg{m}:
      match m:
        case Msg.Line{t}:
          U.Step.Go{St.line(s, t)}
        case Msg.Got{n}:
          U.Step.Go{St.got(s, n)}
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

def fetch(n: Nat, +ch: Chan(U.Ev<Msg>), +k: Nat) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.sleep(120)
        R.Cli.post(Msg, ch, Msg.Got{Nat.mul(k, 5n)})
        fetch(p, ch, 1n+k)

def work(c: Chan(U.Ev<Msg>)) -> IO(Unit):
  +ch = c
  do IO<Unit>:
    IO.sleep(300)
    R.Cli.post(Msg, ch, Msg.Line{"resolved 0.4.0 (engine 0.4.0, Bend 2.0.40, Bun 1.4.5)"})
    IO.sleep(300)
    R.Cli.post(Msg, ch, Msg.Line{"downloaded 41.2 MB in 3.1 s"})
    fetch(20n, ch, 1n)

def main() -> IO(Unit):
  do IO<Unit>:
    s : St <- R.Cli.run(~St, ~Msg, ~U.Cli{view, update, no_keys}, St{Nil{}, 0n, 0n, False{}}, work, 80)
    IO.pure(Unit, Unit{})
