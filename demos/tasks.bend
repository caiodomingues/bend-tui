# tasks: a task list as listr2 draws it. Subtasks show while their
# parent runs, a running task shows its last output line under it, and
# a finished top task is printed once above the live list: collapsed to
# one line when it went well, with its subtasks when one failed. Piped,
# each top task comes out as it finishes.
#
#   bend demos/tasks.bend
#   bend demos/tasks.bend | cat

import Base
import ../../bend-tty/tty.bend as T
import ../tui.bend as U
import ../run.bend as R

type St is Data:
  St{done: List<&2, U.View>, live: List<&2, U.Task>, tick: Nat}

type Msg is Data:
  Msg.Edit{path: List<&2, Nat>, e: U.Task.Edit}
  Msg.Seal{}

def tasks() -> List<&2, U.Task>:
  [U.Task.group("install dependencies", [U.Task.of("resolve versions"), U.Task.of("fetch packages")]),
   U.Task.group("build", [U.Task.of("compile shaders"), U.Task.of("bundle assets"), U.Task.of("write manifest")]),
   U.Task.group("upload", [U.Task.of("sign bundle"), U.Task.of("push to registry")]),
   U.Task.of("notify")]

def view(s: St) -> U.Screen:
  match s:
    case St{done, live, +tick}:
      U.Screen{done, U.Task.view(tick, live)}

# the first live task, final now, moves above
def St.seal(done: List<&2, U.View>, live: List<&2, U.Task>, +tick: Nat) -> St:
  match live:
    case Nil{}:
      St{done, Nil{}, tick}
    case t <> rest:
      St{List.append(&2, U.View, done, [U.Task.view(tick, [t])]), rest, tick}

def St.msg(s: St, m: Msg) -> St:
  match s:
    case St{done, live, tick}:
      match m:
        case Msg.Edit{path, e}:
          St{done, U.Task.put(live, path, e), tick}
        case Msg.Seal{}:
          St.seal(done, live, tick)

def St.tick(s: St) -> St:
  match s:
    case St{done, live, tick}:
      St{done, live, 1n+tick}

def update(e: U.Ev<Msg>, s: St) -> U.Step<St>:
  match e:
    case U.Ev.Msg{m}:
      U.Step.Go{St.msg(s, m)}
    case U.Ev.Tick{}:
      U.Step.Go{St.tick(s)}
    case U.Ev.Done{}:
      U.Step.End{s}
    case U.Ev.Cancel{}:
      U.Step.End{s}
    case U.Ev.Keys{ks}:
      U.Step.Go{s}

def no_keys(s: St) -> Bool:
  False{}

def to(+ch: Chan(U.Ev<Msg>), path: List<&2, Nat>, st: U.Task.State) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(250)
    R.Cli.post(Msg, ch, Msg.Edit{path, U.Task.To{st}})

def say(+ch: Chan(U.Ev<Msg>), path: List<&2, Nat>, s: String) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(150)
    R.Cli.post(Msg, ch, Msg.Edit{path, U.Task.Say{s}})

def seal(+ch: Chan(U.Ev<Msg>)) -> IO(Unit):
  R.Cli.post(Msg, ch, Msg.Seal{})

def install(+ch: Chan(U.Ev<Msg>)) -> IO(Unit):
  do IO<Unit>:
    to(ch, [0n], U.Task.Run{})
    to(ch, [0n, 0n], U.Task.Run{})
    to(ch, [0n, 0n], U.Task.Ok{})
    to(ch, [0n, 1n], U.Task.Run{})
    say(ch, [0n, 1n], "12 / 40 packages")
    say(ch, [0n, 1n], "31 / 40 packages")
    to(ch, [0n, 1n], U.Task.Ok{})
    to(ch, [0n], U.Task.Ok{})
    seal(ch)

def build(+ch: Chan(U.Ev<Msg>)) -> IO(Unit):
  do IO<Unit>:
    to(ch, [0n], U.Task.Run{})
    to(ch, [0n, 0n], U.Task.Run{})
    to(ch, [0n, 0n], U.Task.Ok{})
    to(ch, [0n, 1n], U.Task.Run{})
    say(ch, [0n, 1n], "packing textures 3 / 8")
    say(ch, [0n, 1n], "packing textures 8 / 8")
    to(ch, [0n, 1n], U.Task.Ok{})
    to(ch, [0n, 2n], U.Task.Run{})
    to(ch, [0n, 2n], U.Task.Ok{})
    to(ch, [0n], U.Task.Ok{})
    seal(ch)

def work(c: Chan(U.Ev<Msg>)) -> IO(Unit):
  +ch = c
  do IO<Unit>:
    install(ch)
    build(ch)
    to(ch, [0n], U.Task.Run{})
    to(ch, [0n, 0n], U.Task.Run{})
    to(ch, [0n, 0n], U.Task.Ok{})
    to(ch, [0n, 1n], U.Task.Run{})
    say(ch, [0n, 1n], "uploading 3.2 MB")
    to(ch, [0n, 1n], U.Task.Fail{"connection refused"})
    to(ch, [0n], U.Task.Fail{""})
    seal(ch)
    to(ch, [0n], U.Task.Skip{"upload failed"})
    seal(ch)

def main() -> IO(Unit):
  do IO<Unit>:
    s : St <- R.Cli.run(~St, ~Msg, ~U.Cli{view, update, no_keys}, St{Nil{}, tasks(), 0n}, work, 80)
    IO.pure(Unit, Unit{})
