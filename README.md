# kjell

A Gleam project exploring building remote shells for your services.

**⚠️ very much prototyping and evaluating if this even makes sense ⚠️**

**I don't think this was a great idea, working on https://github.com/fabjan/myrlang instead.**

The idea is to have an extremely stripped down shell (where library users are
in complete control of what it does), building up from zero instead of trying
to lock down something bigger like the default Erlang shell.

The only things it can do are the commands you supply it with. It is _not_ some
general REPL for Gleam.

## Quick start

```sh
gleam run   # Run an example shell
gleam test  # Run the tests
```

## Example

You could install the `recon` Erlang library and expose a smaller API:

```erlang
-module(example_ffi).

-export([
    scheduler_usage/1,
    longest_message_queues/1
]).

scheduler_usage(LongerWindow) ->
    Milliseconds = case LongerWindow of
        true -> 1000;
        _ -> 100
    end,
    recon:scheduler_usage(Milliseconds).

longest_message_queues(Many) ->
    Count = case Many of
        true -> 100;
        _ -> 5
    end,
    TopK = recon:proc_count(message_queue_len, Count),
    lists:map(
        fun ({Pid, Len, Info}) ->
            {_, MFA} = proplists:lookup(current_function, Info),
            {Pid, Len, MFA}
        end,
        TopK
    ).
```

Via FFI:

```gleam
external fn scheduler_usage(Bool) -> List(#(Int, Float)) =
  "example_ffi" "scheduler_usage"

external fn longest_message_queues(Bool) -> List(#(Pid, Int, #(Atom, Atom, Int))) =
  "example_ffi" "longest_message_queues"
```

And then add it to the `kjell` environment:

```gleam

// We will need something like this for each connecting user,
// authentication is assumed to have been done via SSH.
fn jack_in(username) {
  let env = new_env()
  try env =
    add_command(
      env,
      "schedulers",
      "show scheduler usage",
      fn(cmd: Command) {
        use longer, cmd <- opt.bool(
          cmd,
          "longer-window",
          "use a longer sampling window",
        )
        try longer = longer(cmd)
        let usage = scheduler_usage(longer)
        Ok(render_scheduler_usage(usage))
      },
    )
  try env =
    add_command(
      env,
      "message-queues",
      "show the longest message queues",
      fn(cmd: Command) {
        use more, cmd <- opt.bool(
          cmd,
          "show-more",
          "show a longer list",
        )
        try more = more(cmd)
        let longest = longest_message_queues(more)
        Ok(render_message_queue_list(longest))
      },
    )

  // assuming jacked_in was spawned off to a handler process for the session
  kjell.repl(username <> "> ", env)
}
```

## TODO

- [ ] extract `help` builtin so users have full control of commands
- [ ] provide a REPL usable as a library
- [ ] SSH
