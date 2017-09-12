# Changelog

## v0.2.2

### Enhancements

  * [async with] Print a warning message when using `else` clauses that will never match because all patterns in `async with` will always match.

### Bug fixes

  * [async with] Fix compiler warnings produced when one of the `async with` clauses followed an always match pattern (i.e. `a <- 1`).

## v0.2.1

### Enhancements

  * [async with] Correct documentation regarding `@async_with_timeout` attribute.

## v0.2.0

### Enhancements

  * [async with] Optimize implementation.
  * [async with] Use same timeout exit format as `Task`.

### Bug fixes

  * [async with] Ensure asynchronous execution of all clauses as soon as their dependencies are fulfilled.

### Deprecations

  * [DOT] Deprecate the `DOT` module.
  * [DependencyGraph] Deprecate the `DependencyGraph` module.
  * [DependencyGraph.Vertex] Deprecate the `DependencyGraph.Vertex` module.
  * [Macro.DependencyGraph] Deprecate the `Macro.DependencyGraph` module.
  * [Macro.OutNeighbours] Deprecate the `Macro.OutNeighbours` module.
  * [Macro.Vertex] Deprecate the `Macro.Vertex` module.
  * [Clause] Make the `Clause` module private.
  * [Macro] Make the `Macro` module private.
