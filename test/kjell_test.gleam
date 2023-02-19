import gleam/int
import gleam/result
import gleeunit
import gleeunit/should
import kjell.{add_command, new_env}
import outil/arg
import outil/opt

pub fn main() {
  gleeunit.main()
}

fn cmd_hello(cmd) {
  use whom, cmd <- arg.string(cmd, "whom")

  try whom = whom(cmd)
  Ok("Hello, " <> whom <> "!")
}

fn cmd_plus(cmd) {
  use a, cmd <- arg.int(cmd, "a")
  use b, cmd <- arg.int(cmd, "b")

  try a = a(cmd)
  try b = b(cmd)
  Ok("a + b is " <> int.to_string(a + b))
}

fn cmd_concat(cmd) {
  use a, cmd <- arg.string(cmd, "a")
  use b, cmd <- arg.string(cmd, "b")
  use c, cmd <- opt.bool(cmd, "reverse", "reverse the order of a and b")

  try a = a(cmd)
  try b = b(cmd)
  try c = c(cmd)

  let result = case c {
    False -> a <> b
    True -> b <> a
  }

  Ok(result)
}

pub fn hello_world_test() {
  let cmds =
    new_env()
    |> add_command("hello", "say hi", cmd_hello)

  assert Ok(cmds) = cmds

  kjell.eval("hello goober", cmds)
  |> should.equal("Hello, goober!")
}

pub fn multiple_commands_test() {
  let cmds =
    new_env()
    |> add_command("hello", "say hi", cmd_hello)
    |> result.map(add_command(_, "plus", "add two numbers", cmd_plus))
    |> result.flatten()
    |> result.map(add_command(
      _,
      "concat",
      "concatenate two strings",
      cmd_concat,
    ))
    |> result.flatten()

  assert Ok(cmds) = cmds

  kjell.eval("hello goober", cmds)
  |> should.equal("Hello, goober!")

  kjell.eval("plus 1 2", cmds)
  |> should.equal("a + b is 3")

  kjell.eval("concat foo bar", cmds)
  |> should.equal("foobar")

  kjell.eval("concat foo bar --reverse", cmds)
  |> should.equal("barfoo")
}

pub fn brief_help_test() {
  let cmds =
    new_env()
    |> add_command("hello", "say hi", cmd_hello)
    |> result.map(add_command(_, "plus", "add two numbers", cmd_plus))
    |> result.flatten()

  assert Ok(cmds) = cmds

  kjell.eval("help", cmds)
  |> should.equal(
    "hello -- say hi -- usage: hello <whom>
plus -- add two numbers -- usage: plus <a> <b>
help -- show command help -- usage: help [command]",
  )
}

pub fn detailed_help_test() {
  let cmds =
    new_env()
    |> add_command("hello", "say hi", cmd_hello)

  assert Ok(cmds) = cmds

  kjell.eval("help hello", cmds)
  |> should.equal(
    "hello -- say hi
Usage: hello <whom>",
  )
}

pub fn hides_help_option_test() {
  let cmds =
    new_env()
    |> add_command("concat", "concatenate two strings", cmd_concat)

  assert Ok(cmds) = cmds

  kjell.eval("help concat", cmds)
  |> should.equal(
    "concat -- concatenate two strings
Usage: concat <a> <b>
Options:
  --reverse  reverse the order of a and b (bool, default: false)",
  )
}
