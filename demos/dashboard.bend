# dashboard: three panels side by side (a third of the width each),
# bars that advance on every turn (an update with no keys is a tick),
# a log below. Esc or Ctrl-C quits.
#
#   bend demos/dashboard.bend -o dashboard && ./dashboard
import Base
import ../../bend-tty/tty.bend as T
import ../tui.bend as U

# the turn count; each bar is a phase of it
def step.at(+n: Nat, k: T.Key) -> Maybe<&2, Nat>:
  match k:
    case T.Esc{}:
      None{}
    case other:
      Some{n}

def step(n: Nat, k: T.Key) -> Maybe<&2, Nat>:
  step.at(n, k)

def update(ks: List<&2, T.Key>, n: Nat) -> Maybe<&2, Nat>:
  U.Tui.fold(~Nat, ~step, ks, Some{1n+n})

def panel(title: String, +n: Nat, +period: Nat, +color: U32) -> U.View:
  U.Boxed{title, U.Above{
    U.Text{U.Style.plain(), Nat.show(Nat.mod(n, period)) ++ " / " ++ Nat.show(period)},
    U.Progress{Nat.mod(n, period), period, U.Style.fg(color)},
    1n}}

def view.at(+n: Nat) -> U.View:
  U.Below{
    U.Split{panel("cpu", n, 40n, 42), U.Split{panel("mem", n, 90n, 214), panel("disk", n, 200n, 203), 1n, 2n}, 1n, 3n},
    U.Boxed{"log", U.Lines{U.Style.fg(245), ["turn " ++ Nat.show(n), "Esc quits"]}},
    4n}

def view(n: Nat) -> U.View:
  view.at(n)

def main() -> IO(Unit):
  U.Tui.run(~Nat, ~U.Tui{view, update}, 0n, 100)
