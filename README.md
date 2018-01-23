# AsyncWith

[![Build Status](https://travis-ci.org/fertapric/async_with.svg?branch=master)](https://travis-ci.org/fertapric/async_with)

A modifier for `with` to execute all its clauses in parallel.

## Installation

Add `async_with` to your project's dependencies in `mix.exs`:

```elixir
def deps do
  [{:async_with, "~> 0.2"}]
end
```

And fetch your project's dependencies:

```shell
$ mix deps.get
```

## Usage

_TL;DR: `use AsyncWith` and just write `async` in front of `with`._

Let's start with an example:

```elixir
iex> use AsyncWith
iex>
iex> opts = %{width: 10, height: 15}
iex> async with {:ok, width} <- Map.fetch(opts, :width),
...>            {:ok, height} <- Map.fetch(opts, :height) do
...>   {:ok, width * height}
...> end
{:ok, 150}
```

As in `with/1`, if all clauses match, the `do` block is executed, returning its result. Otherwise the chain is aborted and the non-matched value is returned:

```elixir
iex> use AsyncWith
iex>
iex> opts = %{width: 10}
iex> async with {:ok, width} <- Map.fetch(opts, :width),
...>            {:ok, height} <- Map.fetch(opts, :height) do
...>  {:ok, width * height}
...> end
:error
```

However, using `async with`, the right side of `<-` is always executed inside a new task. As soon as any of the tasks finishes, the task that depends on the previous one will be resolved. In other words, `async with` will solve the dependency graph and write the asynchronous code in the most performant way as possible. It also ensures that, if a clause does not match, any running task is shut down.

In addition, guards can be used in patterns as well:

```elixir
iex> use AsyncWith
iex>
iex> users = %{"melany" => "guest", "bob" => :admin}
iex> async with {:ok, role} when not is_binary(role) <- Map.fetch(users, "bob") do
...>   :ok
...> end
:ok
```

As in `with/1`, variables bound inside `async with` won't leak; "bare expressions" may also be inserted between the clauses:

```elixir
iex> use AsyncWith
iex>
iex> width = nil
iex> opts = %{width: 10, height: 15}
iex> async with {:ok, width} <- Map.fetch(opts, :width),
...>            double_width = width * 2,
...>            {:ok, height} <- Map.fetch(opts, :height) do
...>   {:ok, double_width * height}
...> end
{:ok, 300}
iex> width
nil
```

An `else` option can be given to modify what is being returned from `async with` in the case of a failed match:

```elixir
iex> use AsyncWith
iex>
iex> opts = %{width: 10}
iex> async with {:ok, width} <- Map.fetch(opts, :width),
...>            {:ok, height} <- Map.fetch(opts, :height) do
...>   {:ok, width * height}
...> else
...>   :error ->
...>     {:error, :wrong_data}
...> end
{:error, :wrong_data}
```

If there is no matching `else` condition, then a `AsyncWith.ClauseError` exception is raised.

Order-dependent clauses that do not express their dependency via their used or defined variables could lead to race conditions, as they are executed in separated tasks:

```elixir
use AsyncWith

async with Agent.update(agent, fn _ -> 1 end),
           Agent.update(agent, fn _ -> 2 end) do
  Agent.get(agent, fn state -> state end) # 1 or 2
end
```

[Check the documentation](https://hexdocs.pm/async_with) for more information.

## Documentation

Documentation is available at https://hexdocs.pm/async_with

## Code formatter

[As described in `Code.format_string!/2` documentation](https://hexdocs.pm/elixir/Code.html#format_string!/2-parens-and-no-parens-in-function-calls), Elixir will add parens to all calls except for:

1. calls that have do/end blocks
2. local calls without parens where the name and arity of the local call is also listed under `:locals_without_parens`

`async with` expressions should fall under the first category, because they are similar to `with/1` calls. This means that `async/2` calls should be kept without parens.

This is then the recommended `.formatter.exs` configuration:

```elixir
[
  # Regular formatter configuration
  # ...

  import_deps: [:async_with]
]
```

As an alternative, you can add `async: 1` and `async: 2` directly to the list `:locals_without_parens`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fertapric/async_with. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

### Running tests

Clone the repo and fetch its dependencies:

```shell
$ git clone https://github.com/fertapric/async_with.git
$ cd async_with
$ mix deps.get
$ mix test
```

### Building docs

```shell
$ mix docs
```

## Copyright and License

Copyright 2017 Fernando Tapia Rico

AsyncWith source code is licensed under the [MIT License](LICENSE).
