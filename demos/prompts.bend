# prompts: what `ogw new` will ask, in @clack/prompts' look: a select,
# a multi-select, a confirm and a text input with a real cursor and a
# placeholder. Up/Down or k/j move, Space marks, Enter answers, y/n
# answer a confirm, Esc or Ctrl-C cancels and ends the flow. Each
# answered prompt stays as its title and its answer.
#
#   bend demos/prompts.bend -o prompts && ./prompts

import Base
import ../../bend-tty/tty.bend as T
import ../tui.bend as U
import ../run.bend as R

def cancelled() -> IO(Unit):
  do IO<Unit>:
    IO.print("└  cancelled")
    IO.exit(R.Cli.cancelled_code())

def named(n: Maybe<&2, String>) -> IO(Unit):
  match n:
    case Some{+s}:
      do IO<Unit>:
        R.Cli.print(U.Note.view("next steps", ["cd " ++ s, "ogw dev"]))
        IO.print("└  created " ++ s)
    case None{}:
      cancelled()

def confirmed(y: Maybe<&2, Bool>) -> IO(Unit):
  match y:
    case Some{b}:
      do IO<Unit>:
        n : Maybe<&2, String> <- R.Prompt.text("Project name", "my-game")
        named(n)
    case None{}:
      cancelled()

def featured(f: Maybe<&2, List<&2, Nat>>) -> IO(Unit):
  match f:
    case Some{xs}:
      do IO<Unit>:
        y : Maybe<&2, Bool> <- R.Prompt.confirm("Install dependencies?", True{})
        confirmed(y)
    case None{}:
      cancelled()

def picked(t: Maybe<&2, Nat>) -> IO(Unit):
  match t:
    case Some{i}:
      do IO<Unit>:
        f : Maybe<&2, List<&2, Nat>> <- R.Prompt.multi("Which features?", ["physics", "audio", "networking"])
        featured(f)
    case None{}:
      cancelled()

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("┌  ogw new")
    IO.print("│")
    t : Maybe<&2, Nat> <- R.Prompt.select("Pick a template", ["minimal", "platformer", "puzzle"])
    picked(t)
