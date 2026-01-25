# GQL

A composable query builder for dynamically constructing and manipulating
GraphQL queries, mutations, and subscriptions in Elixir.

## Overview

GQL builds upon [Absinthe](https://github.com/absinthe-graphql/absinthe) to
allow users to dynamically build GraphQL queries. While Absinthe provides
Blueprint-type structs to build schema-specific documents, **GQL focuses on
schemaless building of queries** based on the `Absinthe.Language.Document`
struct.

This library provides a programmatic way to build GraphQL documents as data
structures, similar to how `Ecto.Query` makes SQL queries composable. Instead
of working with static query strings, you can dynamically create, merge, and
transform GraphQL operations using a functional API.

## Installation

Add `gql` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gql, "~> 0.1.0", hex: :gql_builder}
  ]
end
```

Please noteice that the Hex package name and the project name are different,
because the package name gql was already taken.

## Quick Start

### Creating a Basic Query

Start with a new document and add fields:

```elixir
GQL.new()
|> GQL.name("contact")
|> GQL.field(:user)
|> GQL.field(:name, path: [:user])
|> GQL.field(:email, path: [:user])
```

This generates:

```graphql
query contact {
  user {
    email
    name
  }
}
```

### Parsing Existing Queries

Use the `~GQL` sigil to parse an inline GraphQL documents from the Elixir
source:

```elixir
import GQL

~GQL[query { user(id: 19) { id } }]
|> GQL.field(:mailbox_size, path: [:user])
|> GQL.type(:subscription)
```

This generates:

```graphql
subscription {
  user(id: 19) {
    mailbox_size
    id
  }
}
```

The `~GQL` sigil validates syntax at compile time while still allowing runtime
manipulation of the document structure.

## Core Concepts

### Creating Documents

Create a new empty GraphQL document:

```elixir
GQL.new()
```

You can also initialize with options:

```elixir
GQL.new(name: "test", field: "__typename")
```

This generates:

```graphql
query test {
  __typename
}
```

Or build more complex queries inline:

```elixir
GQL.new(
  field: {"posts", alias: "p", args: %{id: 42}},
  field: {:title, alias: "t", path: ["p"]},
  field: {:author, path: "p", alias: "a"}
)
```

This generates:

```graphql
query {
  p: posts(id: 42) {
    t: title
    a: author
  }
}
```

You can take a GraphQL query represented by a binary as the base of the GQL
funcitons:

```elixir
"query { temperature }" |> GQL.argument(:unit, path: "temperature", value: :CELSIUS)
```

This generates:

```graphql
query {
  temperature(unit: CELSIUS)
}
```

### Operation Types

Set the operation type to query, mutation, or subscription:

```elixir
GQL.new(field: :field)
|> GQL.type(:subscription)
```

This generates:

```graphql
subscription {
  field
}
```

### Naming Operations

Assign a name to your operation for better logging and observability:

```elixir
GQL.new(field: :field)
|> GQL.name(:hello)
```

This generates:

```graphql
query hello {
  field
}
```

### Working with Fields

Add fields to your document:

```elixir
GQL.new()
|> GQL.field(:id)
|> GQL.field(:name)
|> GQL.field(:email)
```

This generates:

```graphql
query {
  email
  name
  id
}
```

Use paths to add nested fields:

```elixir
GQL.new()
|> GQL.field(:id, path: ["blogs", "posts"])
```

This creates:

```graphql
query {
  blogs {
    posts {
      id
    }
  }
}
```

### Field Aliases

Add aliases to fields:

```elixir
GQL.new(field: {:posts, alias: "p", args: %{id: 42}})
```

This generates:

```graphql
query {
  p: posts(id: 42)
}
```

### Removing and Replacing Fields

Remove fields from your document:

```elixir
"query { apple { foo bar baz } banana }"
|> GQL.remove_field(:banana)
|> GQL.remove_field(:baz, path: ["apple"])
```

This generates:

```graphql
query {
  apple {
    foo
    bar
  }
}
```

Replace a field with a new definition:

```elixir
"query { user { id name email } }"
|> GQL.replace_field(:user, args: %{id: 42})
```

This generates:

```graphql
query {
  user(id: 42) {
    id
    name
    email
  }
}
```

## Composable Queries

Build queries from reusable components:

```elixir
def base_user_fields(query) do
  query
  |> GQL.field(:id)
  |> GQL.field(:name)
end

def with_posts(query) do
  query
  |> GQL.field(:posts)
  |> GQL.field(:title, path: [:posts])
end

GQL.new(field: :user)
|> base_user_fields()
|> with_posts()
```

This generates:

```graphql
query {
  user {
    id
    name
    posts {
      title
    }
  }
}
```

This composable approach allows you to build complex queries from simple,
testable building blocks, making it easier to maintain and reuse query logic
throughout your application.

## Variables

### Defining Variables

Add variable definitions to your operation:

```elixir
GQL.new()
|> GQL.variable(:id, type: "ID")
|> GQL.field(:user, args: %{id: "$id"})
|> GQL.field(:name, path: [:user])
|> GQL.name(:GetUser)
```

This generates:

```graphql
query GetUser($id: ID!) {
  user(id: $id) {
    name
  }
}
```

### Variable Options

Specify types, defaults, and optionality:

```elixir
GQL.new()
|> GQL.type(:mutation)
|> GQL.variable(:id, type: ID, optional: true)
|> GQL.variable(:key, type: Integer)
|> GQL.variable(:name, default: "Joe")
|> GQL.variable(:age, default: 42)
|> GQL.field(:add_user, args: %{name: "$name", age: "$age", id: "$id"})
```

This generates:

```graphql
mutation($id: ID, $key: Integer!, $name: String! = "Joe", $age: Int! = 42) {
  add_user(name: $name, age: $age, id: $id)
}
```

### Removing Variables

Remove variable definitions:

```elixir
"query hello($id: ID!, $semver: Boolean! = true) { serverVersion(semver: $semver) }"
|> GQL.remove_variable(:id)
```

This generates:

```graphql
query hello($semver: Boolean! = true) {
  serverVersion(semver: $semver)
}
```

### Inlining Variables

Replace variable references with concrete values:

```elixir
"query Q($id: ID!) { get(id: $id) { name } }"
|> GQL.inline_valriables(%{id: 42})
```

This generates:

```graphql
query Q {
  get(id: 42) {
    name
  }
}
```

## Arguments

### Adding Arguments

Attach arguments to fields:

```elixir
"query { hello }"
|> GQL.argument(:who, path: ["hello"], value: "World!")
```

This generates:

```graphql
query {
  hello(who: "World!")
}
```

### Replacing Arguments

Update existing argument values:

```elixir
"query { user(id: 42) { name } }"
|> GQL.replace_argument(:id, path: ["user"], value: 99)
```

This generates:

```graphql
query {
  user(id: 99) {
    name
  }
}
```

### Removing Arguments

Delete specific arguments:

```elixir
"query { user(id: 42, name: \"John\") { email } }"
|> GQL.remove_argument(:name, ["user"])
```

This generates:

```graphql
query {
  user(id: 42) {
    email
  }
}
```

## Directives

Add directives like `@include` or `@skip` to fields:

```elixir
"query { user { name email } }"
|> GQL.directive("include", ["user"], %{if: "$showUser"})
```

This generates:

```graphql
query {
  user @include(if: $showUser) {
    name
    email
  }
}
```

Add directives to nested fields:

```elixir
"query { user { name email } }"
|> GQL.directive("skip", ["user", "email"], %{if: "$hideEmail"})
```

## Fragments

### Named Fragments

Define reusable named fragments:

```elixir
GQL.new()
|> GQL.fragment(:UserFields, :User)
|> GQL.field(:name, path: [:UserFields])
|> GQL.field(:email, path: [:UserFields])
```

This generates:

```graphql
query {
}
fragment UserFields on User {
  email
  name
}
```

### Spreading Fragments

Use fragment spreads to include fragments in queries:

```elixir
GQL.new()
|> GQL.fragment(:UserFields, :User)
|> GQL.field(:name, path: [:UserFields])
|> GQL.field(:email, path: [:UserFields])
|> GQL.field(:user)
|> GQL.spread_fragment(:UserFields, path: [:user])
```

This generates:

```graphql
query {
  user {
    ...UserFields
  }
}
fragment UserFields on User {
  email
  name
}
```

### Removing Fragments

Delete fragment definitions:

```elixir
"query { user { id } }"
|> GQL.fragment(:UserFields, :User)
|> GQL.remove_fragment(:UserFields)
```

This generates:

```graphql
query {
  user {
    id
  }
}
```

### Inline Fragments

Add inline fragments for handling union or interface types:

```elixir
GQL.new()
|> GQL.field(:search, args: %{term: "elixir"})
|> GQL.inline_fragment(:User, path: [:search])
|> GQL.field(:name, path: [:search, {nil, type: :User}])
|> GQL.field(:email, path: [:search, {nil, type: :User}])
|> GQL.inline_fragment(:Post, path: [:search])
|> GQL.field(:title, path: [:search, {nil, type: :Post}])
|> GQL.field(:content, path: [:search, {nil, type: :Post}])
```

This generates:

```graphql
query {
  search(term: "elixir") {
    ... on Post {
      content
      title
    }
    ... on User {
      email
      name
    }
  }
}
```

## Utilities

### Merging Documents

Combine two GraphQL documents:

```elixir
doc1 = "query { user { id } }"
doc2 = "query { posts { title } }"
GQL.merge(doc1, doc2)
```

This generates:

```graphql
query {
  user {
    id
  }
  posts {
    title
  }
}
```

When merging documents with the same fields, they are intelligently
deduplicated and their subfields are merged:

```elixir
doc1 = "query { user { id } }"
doc2 = "query { user { name } }"
GQL.merge(doc1, doc2)
```

This generates:

```graphql
query {
  user {
    id
    name
  }
}
```

### Parsing from Files

Load and parse GraphQL documents from files:

```elixir
GQL.parse_file("/path/to/query.graphql")
```

### Injecting Typenames

Automatically add `__typename` to all object selections:

```elixir
"query { apple { foo bar { baz } } }"
|> GQL.inject_typenames()
```

This generates:

```graphql
query {
  __typename
  apple {
    __typename
    foo
    bar {
      __typename
      baz
    }
  }
}
```

This is particularly useful when working with GraphQL clients that require
typename information for caching and normalization.

## Type Guards

GQL provides a guard to check for valid operation types:

```elixir
import GQL

def my_function(doc, type) when is_operation(type) do
  doc
  |> type(type)
  |> name("My#{type |> to_string() |> String.capitalize()}")
end
```

The `is_operation/1` guard checks if the argument is one of `:query`,
`:mutation`, or `:subscription`.

## Converting to Strings

Documents automatically convert to GraphQL strings:

```elixir
doc = GQL.new(field: :user)
to_string(doc)

# or

"#{doc}"
```

## API Reference

### Document Creation
- `new/1` - Create a new GraphQL document
- `parse/1` - Parse a GraphQL string into a document
- `parse_file/1` - Parse a GraphQL file into a document

### Operation Configuration
- `type/2` - Set operation type (query, mutation, subscription)
- `name/2` - Set operation name

### Variables
- `variable/3` - Add a variable definition
- `remove_variable/2` - Remove a variable definition
- `inline_valriables/2` - Replace variables with values

### Fields
- `field/3` - Add a field
- `remove_field/3` - Remove a field
- `replace_field/3` - Replace a field

### Arguments
- `argument/3` - Add an argument to a field
- `replace_argument/3` - Update an argument value
- `remove_argument/3` - Remove an argument

### Directives
- `directive/4` - Add a directive to a field

### Fragments
- `fragment/3` - Define a named fragment
- `remove_fragment/2` - Remove a fragment definition
- `spread_fragment/3` - Spread a fragment into a selection
- `inline_fragment/3` - Add an inline fragment

### Utilities
- `merge/2` - Merge two documents
- `inject_typenames/1` - Add __typename to all selections
- `is_operation/1` - Guard for operation types

