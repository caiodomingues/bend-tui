# todo: a list and an input. Type and Enter to add; Up/Down select;
# Tab marks the selection done; Delete removes it; Esc quits.
#
#   bend demos/todo.bend -o todo && ./todo
import Base
import ../../bend-tty/tty.bend as T
import ../tui.bend as U

type Todo is Data:
  Todo{items: List<&2, String>, sel: Nat, input: String}

def init() -> Todo:
  Todo{["[ ] read the guide", "[ ] prove a law"], 0n, ""}

# the item at n with its mark flipped: "[ ] " to "[x] " and back
def toggle(s: String) -> String:
  match s:
    case SCon{Chr{91}, SCon{Chr{32}, t}}:
      "[x" ++ t
    case SCon{Chr{91}, SCon{Chr{120}, t}}:
      "[ " ++ t
    case other:
      other

def toggle_at(items: List<&2, String>, n: Nat) -> List<&2, String>:
  match items n:
    case Nil{} m:
      Nil{}
    case s <> t 0n:
      toggle(s) <> t
    case s <> t 1n+p:
      s <> toggle_at(t, p)

def remove_at(items: List<&2, String>, n: Nat) -> List<&2, String>:
  match items n:
    case Nil{} m:
      Nil{}
    case s <> t 0n:
      t
    case s <> t 1n+p:
      s <> remove_at(t, p)

# the last character dropped
def backspace(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{c, SNil{}}:
      SNil{}
    case SCon{c, t}:
      SCon{c, backspace(t)}

def sel_down(+sel: Nat, +n: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(1n+sel, n), 1n+sel, sel)

def add(+items: List<&2, String>, +input: String) -> List<&2, String>:
  match input:
    case SNil{}:
      items
    case other:
      List.append(&2, String, items, ["[ ] " ++ other])

def step.at(+m: Todo, k: T.Key) -> Maybe<&2, Todo>:
  match m k:
    case m2 T.Esc{}:
      None{}
    case Todo{items, sel, input} T.Up{}:
      Some{Todo{items, Nat.sub(sel, 1n), input}}
    case Todo{items, sel, input} T.Down{}:
      Some{Todo{items, sel_down(sel, List.length(&2, String, items)), input}}
    case Todo{items, sel, input} T.Tab{}:
      Some{Todo{toggle_at(items, sel), sel, input}}
    case Todo{items, sel, input} T.Delete{}:
      Some{Todo{remove_at(items, sel), Nat.sub(sel, 1n), input}}
    case Todo{items, sel, input} T.Enter{}:
      Some{Todo{add(items, input), sel, ""}}
    case Todo{items, sel, input} T.Backspace{}:
      Some{Todo{items, sel, backspace(input)}}
    case Todo{items, sel, input} T.Char{c}:
      Some{Todo{items, sel, input ++ SCon{Chr{c}, ""}}}
    case m2 other:
      Some{m2}

# the shape Tui.fold wants: an affine model parameter
def step(m: Todo, k: T.Key) -> Maybe<&2, Todo>:
  step.at(m, k)

def update(ks: List<&2, T.Key>, m: Todo) -> Maybe<&2, Todo>:
  U.Tui.fold(~Todo, ~step, ks, Some{m})

def view.at(+m: Todo) -> U.View:
  match m:
    case Todo{items, sel, input}:
      U.Boxed{"todo", U.Below{
        U.Menu{items, sel, 0n},
        U.Above{U.Text{U.Style.fg(245), "Enter adds, Tab marks, Delete removes, Esc quits"}, U.Input{input, String.length(input)}, 1n},
        2n}}

def view(m: Todo) -> U.View:
  view.at(m)

def main() -> IO(Unit):
  U.Tui.run(~Todo, ~U.Tui{view, update}, init(), 50)
