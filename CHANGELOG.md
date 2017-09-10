# Changelog

## v0.2.1

### 1. Enhancements

  * [async with] Correct documentation regarding `@async_with_timeout` attribute

## v0.2.0

### 1. Enhancements

  * [async with] Optimize implementation
  * [async with] Use same timeout exit format as `Task`

### 2. Bug fixes

  * [async with] Ensure asynchronous execution of all clauses as soon as their dependencies are fulfilled

### 3. Deprecations

  * [DOT] Deprecate the `DOT` module.
  * [DependencyGraph] Deprecate the `DependencyGraph` module.
  * [DependencyGraph.Vertex] Deprecate the `DependencyGraph.Vertex` module.
  * [Macro.DependencyGraph] Deprecate the `Macro.DependencyGraph` module.
  * [Macro.OutNeighbours] Deprecate the `Macro.OutNeighbours` module.
  * [Macro.Vertex] Deprecate the `Macro.Vertex` module.
  * [Clause] Make the `Clause` module private.
  * [Macro] Make the `Macro` module private.
