# AsyncWith

[![Build Status](https://travis-ci.org/fertapric/async_with.svg?branch=master)](https://travis-ci.org/fertapric/async_with)

A modifier for `with` to execute all its clauses in parallel.

## Installation

Add `async_with` to your project's dependencies in `mix.exs`:

```elixir
def deps do
  [{:async_with, "~> 0.1"}]
end
```

And fetch your project's dependencies:

```shell
$ mix deps.get
```

## Usage

_TL;DR: just write `async` in front of `with`._

Let's start with an example:

```elixir
iex> opts = %{width: 10, height: 15}
iex> async with {:ok, width} <- Map.fetch(opts, :width),
...>            {:ok, height} <- Map.fetch(opts, :height) do
...>   {:ok, width * height}
...> end
{:ok, 150}
```

As in `with/1`, if all clauses match, the `do` block is executed, returning its result. Otherwise the chain is aborted and the non-matched value is returned:

```elixir
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
iex> users = %{"melany" => "guest", "bob" => :admin}
iex> async with {:ok, role} when not is_binary(role) <- Map.fetch(users, "bob") do
...>   :ok
...> end
:ok
```

As in `with/1`, variables bound inside `async with` won't leak; "bare expressions" may also be inserted between the clauses:

```elixir
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
async with Agent.update(agent, fn _ -> 1 end),
           Agent.update(agent, fn _ -> 2 end) do
  Agent.get(agent, fn state -> state end) # 1 or 2
end
```

[Check the documentation](https://hexdocs.pm/async_with) for more information.

## Documentation

Documentation is available at https://hexdocs.pm/async_with

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

## License

**AsyncWith** is released under the [MIT License](https://opensource.org/licenses/MIT).

## Author

Fernando Tapia Rico, [@fertapric](https://twitter.com/fertapric)
