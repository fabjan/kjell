////   Copyright 2023 Fabian Bergström
////
////   Licensed under the Apache License, Version 2.0 (the "License");
////   you may not use this file except in compliance with the License.
////   You may obtain a copy of the License at
////
////       http://www.apache.org/licenses/LICENSE-2.0
////
////   Unless required by applicable law or agreed to in writing, software
////   distributed under the License is distributed on an "AS IS" BASIS,
////   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
////   See the License for the specific language governing permissions and
////   limitations under the License.

import gleam/erlang
import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/regex
import gleam/string
import outil.{
  Command, CommandError, CommandLineError, CommandReturn, Help, command,
}
import outil/error.{MalformedArgument, MissingArgument}
import outil/arg

/// The implementation of a shell command.
///
/// Example:
///
///   fn cmd_repeat_foo(cmd: Command) -> Result(String, CommandReturn(String)) {
///     let foo_param, cmd = arg.string(cmd, "foo")
///     let bar_param, cmd = arg.int(cmd, "bar")
///
///     try foo <- foo_param(cmd)
///     try bar <- bar_param(cmd)
///
///     Ok(string.repeat(foo, bar))
///   }
pub type CommandDefinition =
  fn(Command) -> Result(String, CommandReturn(String))

/// Internal representation of a shell command.
type ShellCommand =
  fn(List(String)) -> Result(String, CommandReturn(String))

/// A shell environment.
pub type Environment {
  Environment(cmds: Map(String, ShellCommand))
}

/// Create a new environment for shell commands.
pub fn new_env() -> Environment {
  Environment(cmds: map.new())
}

/// Add a new command to the environment.
pub fn add_command(
  env: Environment,
  name: String,
  desc: String,
  run: CommandDefinition,
) -> Result(Environment, String) {
  let reserved_names = ["help"]

  try _ = case list.contains(reserved_names, name) {
    True -> Error("Reserved command name: " <> name)
    False -> Ok(Nil)
  }

  let impl = fn(args: List(String)) {
    use cmd <- command(name, desc, args)
    run(cmd)
  }

  let env = Environment(cmds: map.insert(env.cmds, name, impl))

  Ok(env)
}

/// Evaluate a shell command line with the given command definitions.
///
/// The command line string is split on whitespace and the first
/// argument is used as the command name. The rest of the arguments
/// are passed to the command function.
///
/// There is a special command "help" that can be used to show help
/// text for all commands or a specific command.
pub fn eval(commandline: String, env: Environment) -> String {
  assert Ok(whitespace) = regex.from_string("\\s+")
  let argv =
    regex.split(whitespace, commandline)
    |> list.filter(fn(s) { !string.is_empty(s) })

  let info = "Type 'help' for help."

  let cmds = env.cmds
  case argv {
    ["help"] -> show_help(cmds)
    ["help", "help"] -> show_help(cmds)
    ["help", cmd] -> describe_command(cmd, cmds)
    [arg0, ..args] ->
      case map.get(cmds, arg0) {
        Ok(f) -> map_command_result(f(args))
        Error(Nil) -> "ERROR: command not found (" <> arg0 <> ")\n" <> info
      }
    _ -> "ERROR: no command given\n" <> info
  }
}

fn show_help(cmds: Map(String, ShellCommand)) -> String {
  map.to_list(cmds)
  |> list.map(fn(command) {
    let #(_, cmd) = command
    case parse_usage(cmd) {
      Ok(CommandInfo(name, description, usage, _)) ->
        name <> " -- " <> description <> " -- usage: " <> usage
      Error(_) -> "ERROR: cannot parse help text"
    }
  })
  |> string.join("\n")
  |> string.append("\nhelp -- show command help -- usage: help [command]")
}

fn describe_command(name: String, cmds: Map(String, ShellCommand)) -> String {
  case map.get(cmds, name) {
    Ok(cmd) ->
      case parse_usage(cmd) {
        Ok(info) -> unparse_usage(info)
        Error(_) -> "ERROR: cannot parse help text"
      }
    Error(_) -> "ERROR: command not found (" <> name <> ")"
  }
}

type CommandInfo {
  CommandInfo(
    name: String,
    description: String,
    usage: String,
    options: List(String),
  )
}

// This is a hack since outil doesn't expose the command in a
// structured way. But it should be good enough.
fn parse_usage(cmd: ShellCommand) -> Result(CommandInfo, Nil) {
  try usage = case cmd(["--help"]) {
    Error(Help(s)) -> Ok(s)
    Error(_) -> Error(Nil)
    Ok(_) -> Error(Nil)
  }

  try #(name, description) = string.split_once(usage, "--")
  try #(description, usage) = string.split_once(description, "Usage: ")
  try #(usage, options) = string.split_once(usage, "Options:\n")

  let options =
    string.split(options, "\n")
    |> list.filter(fn(s) { !string.starts_with(s, "  -h, --help") })
    |> list.map(fn(s) { string.trim(s) })
    |> list.filter(fn(s) { !string.is_empty(s) })

  Ok(CommandInfo(
    name: string.trim(name),
    description: string.trim(description),
    usage: string.trim(usage),
    options: options,
  ))
}

// In kjell we want to show the help text in a more compact way.
fn unparse_usage(info: CommandInfo) -> String {
  let brief = info.name <> " -- " <> info.description
  let usage = "Usage: " <> info.usage
  let options = case info.options {
    [] -> ""
    _ ->
      "\nOptions:\n" <> {
        info.options
        |> list.map(fn(s) { "  " <> s })
        |> string.join("\n")
      }
  }

  brief <> "\n" <> usage <> options
}

fn map_command_result(result: Result(String, CommandReturn(String))) -> String {
  case result {
    Ok(s) -> s
    Error(CommandLineError(MalformedArgument(name, bad), _)) ->
      "ERROR: " <> name <> " is malformed (" <> bad <> ")"
    Error(CommandLineError(MissingArgument(name), _)) ->
      "ERROR: " <> name <> " is missing"
    Error(CommandError(s)) -> "ERROR: command failed (" <> s <> ")"
    Error(_) -> "ERROR: unexpected error"
  }
}

pub fn main() {
  io.println("Welcome to kjell!")
  io.println("Type 'help' for help.")

  let echo = fn(cmd: Command) {
    use s, cmd <- arg.string(cmd, "s")
    try s = s(cmd)
    Ok(s)
  }

  let env = new_env()
  try env = add_command(env, "echo", "echo one string", echo)

  repl("kjell> ", env)
}

// this is Erlang only for now
pub fn repl(prompt: String, env: Environment) {
  case erlang.get_line(prompt) {
    Error(_) -> Error("Failed to read line")
    Ok(commandline) -> {
      io.println(eval(commandline, env))
      repl(prompt, env)
    }
  }
}
