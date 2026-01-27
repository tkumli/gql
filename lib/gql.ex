alias Absinthe.Language.{Document, OperationDefinition, SelectionSet}
alias Absinthe.Language.{Field, Argument, Variable, VariableDefinition}
alias Absinthe.Language.{NonNullType, NamedType, Fragment, InlineFragment, FragmentSpread}

alias Absinthe.Language.{
  StringValue,
  BooleanValue,
  IntValue,
  FloatValue,
  EnumValue,
  ListValue,
  ObjectValue,
  ObjectField,
  NullValue
}

defmodule GQL do
  @gql inspect(__MODULE__)

  @moduledoc """
  A composable query builder for dynamically constructing and manipulating
  GraphQL queries, mutations, and subscriptions.

  `#{@gql}` provides a programmatic way to build GraphQL documents as data
  structures, similar to how `Ecto.Query` makes SQL queries composable. Instead
  of working with static query strings, you can dynamically create, merge, and
  transform GraphQL operations using a functional API.

  ## Basic Usage

  Start with a new document and add fields:

      iex> #{@gql}.new()
      ...> |> #{@gql}.name("contact")
      ...> |> #{@gql}.field(:user)
      ...> |> #{@gql}.field(:name, path: [:user])
      ...> |> #{@gql}.field(:email, path: [:user])
      ...> |> to_string()
      \"\"\"
      query contact {
        user {
          name
          email
        }
      }
      \"\"\"

  ## Composable Queries

  Build queries from reusable components:

      def base_user_fields(query) do
        query
        |> #{@gql}.field(:id)
        |> #{@gql}.field(:name)
      end

      def with_posts(query) do
        query
        |> #{@gql}.field(:posts)
        |> #{@gql}.field(:title, path: [:posts])
      end

      #{@gql}.new(field: :user)
      |> base_user_fields()
      |> with_posts()

  The result is

      query {
        user
        id
        name
        posts {
          title
        }
      }

  This composable approach allows you to build complex queries from simple,
  testable building blocks, making it easier to maintain and reuse query logic
  throughout your application.

  ## Working with Variables

  Define variables for dynamic queries:

      #{@gql}.new()
      |> #{@gql}.variable(:id, type: "ID")
      |> #{@gql}.field(:user, args: %{id: "$id"})
      |> #{@gql}.field(:name, path: [:user])
      |> #{@gql}.name(:GetUser)

  The query built is this:

      query GetUser($id: ID!) {
        user(id: $id) {
          name
        }
      }


  ## Parsing Existing Documents

  Parse and manipulate existing GraphQL documents:

      ~GQL[query { user(id: 19) { id } }]
      |> #{@gql}.field(:mailbox_size, path: [:user])
      |> #{@gql}.type(:subscription)

  It generates a subscription as follows:

      subscription {
        user(id: 19) {
          id
          mailbox_size
        }
      }

  The `~GQL` sigil validates syntax at compile time while still allowing
  runtime manipulation of the document structure.
  """

  @doc """
  `~GQL` sigil for creating syntax-validated GraphQL request documents.

  ### Examples:

      iex> import #{inspect(__MODULE__)}, only: [sigil_GQL: 2]
      iex> ~GQL[ query get_score($id: ID!) { user(id: $id) { name score { min max current } } } ]
      ...>   |> to_string()
      \"\"\"
      query get_score($id: ID!) {
        user(id: $id) {
          name
          score {
            min
            max
            current
          }
        }
      }
      \"\"\"

  """
  def sigil_GQL(graphql, opts) do
    case Absinthe.Sigil.sigil_GQL(graphql, opts) do
      {:error, _} = error -> error
      str -> parse(str)
    end
  end

  @doc """
  A guard that checks if the argument is one of the `:query`, `:mutation` or
  `:subscription` atoms.

      iex> for i <- [:query, :mutation, :subscription, :reduction, 123, "hello"],
      ...>   do: #{@gql}.is_operation(i)
      [true, true, true, false, false, false]

  """
  defguard is_operation(type) when type in [:query, :mutation, :subscription]

  @base %Document{
    definitions: [
      %OperationDefinition{
        operation: :query,
        selection_set: %SelectionSet{selections: []}
      }
    ]
  }

  @doc """
  Initializes a new, empty #{@gql} document.

      iex> #{@gql}.new(field: "x") |> to_string()
      \"\"\"
      query {
        x
      }
      \"\"\"

  Options can be used to populate the query:

      iex> #{@gql}.new(name: "test", field: "__typename") |> to_string()
      \"\"\"
      query test {
        __typename
      }
      \"\"\"

      iex> #{@gql}.new(
      ...>   field: {"posts", alias: "p", args: %{id: 42}},
      ...>   field: {:title, alias: "t", path: ["p"]},
      ...>   field: {:author, path: "p", alias: "a"}) |> to_string()
      \"\"\"
      query {
        p: posts(id: 42) {
          t: title
          a: author
        }
      }
      \"\"\"

  The `fields` option allows nested field definitions:

      iex> #{@gql}.new(field: {:posts, fields: [:title, {:author, fields: [:name, :email]}]}) |> to_string()
      \"\"\"
      query {
        posts {
          title
          author {
            name
            email
          }
        }
      }
      \"\"\"

  Inline fragments can also be added with the `fields` option:

      iex> #{@gql}.new(
      ...>   field: :x,
      ...>   fragment: [type: :Author, path: "x", fields: [:name, {:email, alias: "mail"}]]) |> to_string()
      \"\"\"
      query {
        x {
          ... on Author {
            name
            mail: email
          }
        }
      }
      \"\"\"

  """
  def new(opts \\ []) do
    Enum.reduce(opts, @base, fn {function, arg}, doc ->
      args =
        cond do
          is_tuple(arg) -> Tuple.to_list(arg)
          is_list(arg) and Keyword.keyword?(arg) -> [arg]
          is_list(arg) -> arg
          true -> List.wrap(arg)
        end

      arity = length(args) + 1

      if Kernel.function_exported?(__MODULE__, function, arity) do
        apply(__MODULE__, function, [doc | args])
      else
        raise ArgumentError, "Function #{function}/#{arity} not found."
      end
    end)
  end

  @doc """
  Parses a GraphQL document into the internal representation.

      iex> #{@gql}.parse("query { field }") |> to_string()
      \"\"\"
      query {
        field
      }
      \"\"\"

  """
  def parse(%Document{} = doc), do: doc

  def parse("" <> str) do
    with {:ok, tokens} <- Absinthe.Lexer.tokenize(str),
         {:ok, parsed} <- :absinthe_parser.parse(tokens) do
      parsed
    end
  end

  @doc """
  Parses a GraphQL document from a file into the internal representation.

      iex> File.write!("/tmp/query.graphql", "query { posts { title author } }")
      iex> #{@gql}.parse_file("/tmp/query.graphql") |> to_string()
      \"\"\"
      query {
        posts {
          title
          author
        }
      }
      \"\"\"

  """
  def parse_file(filename) do
    with {:ok, content} <- File.read(filename) do
      parse(content)
    end
  end

  @doc """
  Sets the operation type of the document to :query, :mutation, or :subscription.

      iex> #{@gql}.new(field: :field) |> #{@gql}.type(:subscription) |> to_string()
      \"\"\"
      subscription {
        field
      }
      \"\"\"

  """
  def type(doc, type) when is_operation(type) do
    doc = parse(doc)

    %{
      doc
      | definitions:
          for definition <- doc.definitions do
            %{definition | operation: type}
          end
    }
  end

  @doc """
  Assigns a name to the GraphQL operation for better logging and server-side observability.

      iex> #{@gql}.new(field: :field) |> #{@gql}.name(:hello) |> to_string()
      \"\"\"
      query hello {
        field
      }
      \"\"\"

  """
  def name(doc, name) do
    doc = parse(doc)
    name = to_string(name)

    %{
      doc
      | definitions:
          for definition <- doc.definitions do
            %{definition | name: name}
          end
    }
  end

  @doc """
  Adds a variable definition to the operation header with its type and an optional default value.

      iex> #{@gql}.new()
      ...> |> #{@gql}.type(:mutation)
      ...> |> #{@gql}.variable(:id, type: ID, optional: true)
      ...> |> #{@gql}.variable(:key, type: Integer)
      ...> |> #{@gql}.variable(:name, default: "Joe")
      ...> |> #{@gql}.variable(:age, default: 42)
      ...> |> #{@gql}.field(:add_user, args: %{name: "$name", age: "$age", id: "$id"})
      ...> |> #{@gql}.field(:set_key, args: [key: "$key", value: "hello"])
      ...> |> to_string()
      \"\"\"
      mutation Mutation($id: ID, $key: Integer!, $name: String! = "Joe", $age: Integer! = 42) {
        add_user(id: $id, name: $name, age: $age)
        set_key(key: $key, value: "hello")
      }
      \"\"\"

  """
  def variable(doc, name, opts \\ []) do
    doc = parse(doc)
    {guessed_type, default} = wrap_value(Keyword.get(opts, :default))
    type = Keyword.get(opts, :type, guessed_type || "String")
    type = %NamedType{name: to_type(type)}
    optional = Keyword.get(opts, :optional, false)

    %{
      doc
      | definitions:
          for definition <- doc.definitions do
            %{
              definition
              | variable_definitions:
                  definition.variable_definitions ++
                    [
                      %VariableDefinition{
                        variable: %Variable{name: to_string(name)},
                        type: if(optional, do: type, else: %NonNullType{type: type}),
                        default_value: default
                      }
                    ],
                name: definition.name || String.capitalize(to_string(definition.operation))
            }
          end
    }
  end

  @doc """
  Removes a variable definition from the operation header by its name.

      iex> \"""
      ...>   query hello($id: ID!, $semver: Boolean! = true) {
      ...>     serverVersion(semver: $semver)
      ...>   }
      ...> \"""
      ...> |> #{@gql}.remove_variable(:id)
      ...> |> to_string()
      \"\"\"
      query hello($semver: Boolean! = true) {
        serverVersion(semver: $semver)
      }
      \"\"\"

  """
  def remove_variable(doc, name) do
    doc = parse(doc)
    name = to_string(name)

    %{
      doc
      | definitions:
          for definition <- doc.definitions do
            %{
              definition
              | variable_definitions:
                  Enum.reject(
                    definition.variable_definitions,
                    &match?(%{variable: %{name: ^name}}, &1)
                  )
            }
          end
    }
  end

  @doc """
  Appends a field to the document.

      iex> "query { __typename }" |> #{@gql}.field(:id) |> to_string()
      "query {
        __typename
        id
      }
      "

  The place of the new field is described by the `path` option. If the path
  is not supplied or is an empty list, the field is placed in the root selection
  set of the document.

      iex> import #{@gql}
      iex> new() |> field(:id, path: ["blogs", "posts"]) |> to_string()
      "query {
        blogs {
          posts {
            id
          }
        }
      }
      "

  You can also add fields to named fragments by using the fragment name as the
  first element of the path:

      iex> import #{@gql}
      iex> new()
      ...> |> field(:x)
      ...> |> fragment(name: :UserFields, type: :User)
      ...> |> field(:name, path: [:UserFields])
      ...> |> field(:email, path: [:UserFields])
      ...> |> to_string() |> String.replace(~r/\\n[ ]*\\n/m, "\\n")
      \"\"\"
      query {
        x
      }
      fragment UserFields on User {
        name
        email
      }
      \"\"\"

  The `fields` option allows you to specify subfields directly:

      iex> import #{@gql}
      iex> new() |> field(:foo, fields: [:bar, :baz]) |> to_string()
      \"\"\"
      query {
        foo {
          bar
          baz
        }
      }
      \"\"\"

  Subfield definitions support the same options as the main field definition,
  including `alias` and `args`:

      iex> import #{@gql}
      iex> new() |> field(:user, fields: [:id, {:name, alias: "fullName"}]) |> to_string()
      \"\"\"
      query {
        user {
          id
          fullName: name
        }
      }
      \"\"\"

      iex> import #{@gql}
      iex> new() |> field(:users, fields: [{:user, args: %{id: 42}, alias: "u"}, :name]) |> to_string()
      \"\"\"
      query {
        users {
          u: user(id: 42)
          name
        }
      }
      \"\"\"

  The `path` option is not allowed in subfield definitions:

      iex> import #{@gql}
      iex> new() |> field(:foo, fields: [{:bar, path: [:baz]}])
      ** (ArgumentError) the `path` option is not allowed in subfield definitions

  """
  def field(doc, name, opts \\ []) do
    doc = parse(doc)
    name = to_string(name)
    alias = Keyword.get(opts, :alias)
    path = Keyword.get(opts, :path, []) |> List.wrap()
    args = Keyword.get(opts, :args, [])
    subfields = Keyword.get(opts, :fields, [])

    field = %Field{name: name, alias: alias && to_string(alias), arguments: arguments(args)}

    # Check if the first path element is a fragment name
    {target_filter, field_path} =
      case path do
        [first | rest] ->
          first_str = to_string(first)
          # Check if this matches a fragment definition
          has_fragment =
            Enum.any?(doc.definitions, fn
              %Fragment{name: ^first_str} -> true
              _ -> false
            end)

          if has_fragment do
            # Target only this fragment, and don't navigate into it as a field
            {Access.filter(&match?(%Fragment{name: ^first_str}, &1)), rest}
          else
            # Target only operation definitions, use full path
            {Access.filter(&match?(%OperationDefinition{}, &1)), path}
          end

        [] ->
          # No path, target operation definitions
          {Access.filter(&match?(%OperationDefinition{}, &1)), []}
      end

    optic =
      [
        access_key(:definitions, nil, []),
        target_filter,
        for path_element <- field_path do
          build_path_navigation(path_element)
        end,
        access_key(:selection_set, nil, %SelectionSet{}),
        Access.key(:selections, [])
      ]
      |> List.flatten()

    doc = update_in(doc, optic, fn selection_list -> (selection_list || []) ++ [field] end)

    # Add subfields if the fields option is present
    field_identifier = alias || name
    subfield_path = path ++ [field_identifier]

    Enum.reduce(subfields, doc, fn subfield_def, acc_doc ->
      add_subfield(acc_doc, subfield_def, subfield_path)
    end)
  end

  # Helper function to add a single subfield
  defp add_subfield(doc, subfield_name, path) when is_atom(subfield_name) do
    field(doc, subfield_name, path: path)
  end

  defp add_subfield(doc, {subfield_name, subfield_opts}, path) when is_list(subfield_opts) do
    if Keyword.has_key?(subfield_opts, :path) do
      raise ArgumentError, "the `path` option is not allowed in subfield definitions"
    end

    field(doc, subfield_name, Keyword.put(subfield_opts, :path, path))
  end

  # Parse path element into normalized {name, alias, args} tuple or inline fragment specification
  defp parse_path_element({nil, opts}) when is_list(opts) do
    {:inline_fragment, Keyword.get(opts, :type)}
  end

  defp parse_path_element({name, opts}) when is_list(opts) do
    {to_string(name), Keyword.get(opts, :alias), Keyword.get(opts, :args, [])}
  end

  defp parse_path_element(name) do
    {to_string(name), nil, []}
  end

  # Helper to build navigation for a single path element
  defp build_path_navigation({nil, opts}) when is_list(opts) do
    type = Keyword.get(opts, :type)
    type_str = type && to_string(type)

    filter =
      if type do
        Access.filter(&match?(%InlineFragment{type_condition: %NamedType{name: ^type_str}}, &1))
      else
        Access.filter(&match?(%InlineFragment{type_condition: nil}, &1))
      end

    [access_key(:selection_set, nil, %SelectionSet{}), access_key(:selections, [], []), filter]
  end

  defp build_path_navigation(path_element) do
    {name, alias_name, args} = parse_path_element(path_element)
    field = %Field{name: name, alias: alias_name && to_string(alias_name), arguments: arguments(args)}

    [
      access_key(:selection_set, nil, %SelectionSet{}),
      access_key(:selections, nil, []),
      access_or_create_field(name, field)
    ]
  end

  # Custom access function that creates a field if it doesn't exist
  defp access_or_create_field(name, default_field) do
    fn
      :get, data, next when is_list(data) ->
        data
        |> Enum.find(&match_field(&1, name))
        |> case do
          nil -> next.(default_field)
          field -> next.(field)
        end

      :get_and_update, data, next when is_list(data) ->
        case Enum.find_index(data, &match_field(&1, name)) do
          nil ->
            case next.(default_field) do
              {get, updated_field} -> {get, data ++ [updated_field]}
              :pop -> {default_field, data}
            end

          index ->
            case next.(Enum.at(data, index)) do
              {get, updated_field} -> {get, List.replace_at(data, index, updated_field)}
              :pop -> {Enum.at(data, index), List.delete_at(data, index)}
            end
        end
    end
  end

  defp match_field(%Field{} = f, name) do
    # If the field has an alias, only match on alias
    # If no alias, match on name
    if f.alias, do: f.alias == name, else: f.name == name
  end

  defp match_field(_, _), do: false

  @doc """
  Attaches an argument to a field identified by its path.

      iex> "query { hello }"
      ...> |> #{@gql}.argument(:who, path: ["hello"], value: "World!")
      ...> |> to_string()
      \"\"\"
      query {
        hello(who: "World!")
      }
      \"\"\"

  """
  def argument(doc, name, opts \\ []) do
    doc = parse(doc)
    name = to_string(name)
    path = Keyword.fetch!(opts, :path) |> List.wrap()
    value = Keyword.fetch!(opts, :value)

    {_type, wrapped_value} = wrap_value(value)
    argument = %Argument{name: name, value: wrapped_value}

    optic = build_field_optic(path, :arguments)
    update_in(doc, optic, fn argument_list -> (argument_list || []) ++ [argument] end)
  end

  @doc """
  Replaces a field or subfield at the specified path with a completely new field definition.

  This function removes the existing field and adds a new one with the same name but potentially
  different arguments, alias, or sub-selections. The field is replaced in-place at the specified path.

      iex> "query { user { id name email } }"
      ...> |> #{@gql}.replace_field(:user, args: %{id: 42})
      ...> |> to_string()
      \"\"\"
      query {
        user(id: 42) {
          id
          name
          email
        }
      }
      \"\"\"

  Nested fields can be replaced by providing a path:

      iex> "query { user { profile { bio avatar } } }"
      ...> |> #{@gql}.replace_field(:profile, path: ["user"], alias: "userProfile")
      ...> |> to_string()
      \"\"\"
      query {
        user {
          userProfile: profile {
            bio
            avatar
          }
        }
      }
      \"\"\"

  """
  def replace_field(doc, name, opts \\ []) do
    doc = parse(doc)
    name = to_string(name)
    path = Keyword.get(opts, :path, []) |> List.wrap()
    alias_name = Keyword.get(opts, :alias)
    args = Keyword.get(opts, :args, [])

    optic = build_field_optic(path, :selections)

    update_in(doc, optic, fn selections ->
      Enum.map(selections || [], fn
        %Field{} = field ->
          # If field has an alias, only match on alias; otherwise match on name
          matches = if field.alias, do: field.alias == name, else: field.name == name

          if matches do
            %{field | alias: alias_name && to_string(alias_name), arguments: arguments(args)}
          else
            field
          end

        other ->
          other
      end)
    end)
  end

  @doc """
  Removes a field and all of its associated sub-selections from the document.

      iex> "query { apple { foo bar baz } banana }"
      ...> |> #{@gql}.remove_field(:banana)
      ...> |> #{@gql}.remove_field(:baz, path: ["apple"])
      ...> |> to_string()
      \"\"\"
      query {
        apple {
          foo
          bar
        }
      }
      \"\"\"

  """
  def remove_field(doc, name, opts \\ []) do
    doc = parse(doc)
    name = to_string(name)
    path = Keyword.get(opts, :path, []) |> List.wrap()

    optic = build_field_optic(path, :selections)

    update_in(doc, optic, fn selections ->
      Enum.reject(selections || [], fn selection ->
        alias_val = Map.get(selection, :alias)
        name_val = Map.get(selection, :name)
        # If has alias, only match on alias; otherwise match on name
        if alias_val, do: alias_val == name, else: name_val == name
      end)
    end)
  end

  @doc """
  Updates the value of an existing argument on a field located at the given path.

  This function replaces the value of an existing argument while keeping the argument name.
  If the argument doesn't exist, it will be added to the field.

      iex> "query { user(id: 42) { name } }"
      ...> |> #{@gql}.replace_argument(:id, path: ["user"], value: 99)
      ...> |> to_string()
      \"\"\"
      query {
        user(id: 99) {
          name
        }
      }
      \"\"\"

  You can update arguments with different types of values:

      iex> "query { posts(limit: 10, published: true) { title } }"
      ...> |> #{@gql}.replace_argument(:limit, path: ["posts"], value: 20)
      ...> |> #{@gql}.replace_argument(:published, path: ["posts"], value: false)
      ...> |> to_string()
      \"\"\"
      query {
        posts(limit: 20, published: false) {
          title
        }
      }
      \"\"\"

  """
  def replace_argument(doc, name, opts \\ []) do
    path = Keyword.fetch!(opts, :path)

    doc
    |> remove_argument(name, path)
    |> argument(name, opts)
  end

  @doc """
  Deletes a specific argument from a field located at the given path.

      iex> "query { user(id: 42, name: \\"John\\") { email } }"
      ...> |> #{@gql}.remove_argument(:name, ["user"])
      ...> |> to_string()
      \"\"\"
      query {
        user(id: 42) {
          email
        }
      }
      \"\"\"

  """
  def remove_argument(doc, key, path) do
    doc = parse(doc)
    path = List.wrap(path)
    key = to_string(key)

    optic = build_field_optic(path, :arguments)

    update_in(doc, optic, fn arguments ->
      Enum.reject(arguments || [], &(&1.name == key))
    end)
  end

  @doc """
  Adds a directive, such as @include or @skip, to a field or to the operation
  itself at the specified path.

  Directives are annotations that can be attached to fields or operations to
  provide additional metadata or modify execution behavior. Common directives
  include `@include`, `@skip`, and `@deprecated`.

  To add a directive to the operation itself (the root
  query/mutation/subscription), use an empty path `[]`. This allows you to
  write queries like `query @directive { ... }`.

  ## Examples

  Adding a directive to the operation itself (root):

      iex> "query { user { name } }"
      ...> |> #{@gql}.directive("cached", [])
      ...> |> to_string()
      \"\"\"
      query @cached {
        user {
          name
        }
      }
      \"\"\"

  Adding a directive with arguments to the root operation:

      iex> #{@gql}.new(field: :user)
      ...> |> #{@gql}.field(:name, path: [:user])
      ...> |> #{@gql}.directive("rateLimit", [], %{max: 100})
      ...> |> to_string()
      \"\"\"
      query @rateLimit(max: 100) {
        user {
          name
        }
      }
      \"\"\"

  Adding an @include directive with a condition to a field:

      iex> "query { user { name email } }"
      ...> |> #{@gql}.directive("include", ["user"], %{if: "$showUser"})
      ...> |> to_string()
      \"\"\"
      query {
        user @include(if: $showUser) {
          name
          email
        }
      }
      \"\"\"

  Adding a @skip directive to a nested field:

      iex> "query { user { name email } }"
      ...> |> #{@gql}.directive("skip", ["user", "email"], %{if: "$hideEmail"})
      ...> |> to_string()
      \"\"\"
      query {
        user {
          name
          email @skip(if: $hideEmail)
        }
      }
      \"\"\"

  Adding a directive without arguments:

      iex> "query { deprecatedField }"
      ...> |> #{@gql}.directive(:deprecated, ["deprecatedField"])
      ...> |> to_string()
      \"\"\"
      query {
        deprecatedField @deprecated
      }
      \"\"\"

  """
  def directive(doc, name, path, directive_args \\ []) do
    alias Absinthe.Language.Directive

    doc = parse(doc)
    path = List.wrap(path)
    name = to_string(name)

    directive = %Directive{name: name, arguments: arguments(directive_args)}

    case path do
      [] ->
        # Empty path means add directive to the operation itself
        %{
          doc
          | definitions:
              for definition <- doc.definitions do
                case definition do
                  %OperationDefinition{} = op_def ->
                    %{op_def | directives: (op_def.directives || []) ++ [directive]}

                  other ->
                    other
                end
              end
        }

      _ ->
        # Non-empty path means add directive to a field
        optic = build_field_optic(path, :directives)
        update_in(doc, optic, fn directive_list -> (directive_list || []) ++ [directive] end)
    end
  end

  @doc """
  Creates either a named fragment definition or adds an inline fragment to a selection set.

  This function has two modes of operation based on the options provided:

  - **Named fragments** (when `name` and `type` are provided): Creates a reusable fragment
    definition that can be spread across multiple queries using `spread_fragment/3`.
  - **Inline fragments** (when `path` and `type` are provided): Adds an inline fragment
    for handling union or interface types at a specific path.

  ## Named Fragment Examples

  Creating a basic named fragment on a User type:

      iex> #{@gql}.new(field: "x")
      ...> |> #{@gql}.fragment(name: :UserFields, type: :User)
      ...> |> #{@gql}.field("y", path: [:UserFields])
      ...> |> to_string() |> String.replace("\\n\\n", "\\n")
      \"\"\"
      query {
        x
      }
      fragment UserFields on User {
        y
      }
      \"\"\"

  Creating multiple named fragments:

      iex> #{@gql}.new(field: "x")
      ...> |> #{@gql}.fragment(name: :BasicUser, type: :User)
      ...> |> #{@gql}.fragment(name: :PostInfo, type: :Post)
      ...> |> #{@gql}.field("y", path: :BasicUser)
      ...> |> #{@gql}.field("z", path: :PostInfo)
      ...> |> to_string() |> String.replace("\\n\\n", "\\n")
      \"\"\"
      query {
        x
      }
      fragment BasicUser on User {
        y
      }
      fragment PostInfo on Post {
        z
      }
      \"\"\"

  ## Inline Fragment Examples

  Adding an inline fragment to handle a union type:

      iex> #{@gql}.new()
      ...> |> #{@gql}.field(:search, args: %{term: "elixir"})
      ...> |> #{@gql}.fragment(type: :User, path: [:search])
      ...> |> #{@gql}.field(:name, path: [:search, {nil, type: :User}])
      ...> |> #{@gql}.field(:email, path: [:search, {nil, type: :User}])
      ...> |> #{@gql}.fragment(type: :Post, path: [:search])
      ...> |> #{@gql}.field(:title, path: [:search, {nil, type: :Post}])
      ...> |> #{@gql}.field(:content, path: [:search, {nil, type: :Post}])
      ...> |> to_string()
      \"\"\"
      query {
        search(term: "elixir") {
          ... on User {
            name
            email
          }
          ... on Post {
            title
            content
          }
        }
      }
      \"\"\"

  Adding an inline fragment without a type condition (for interfaces):

      iex> #{@gql}.new()
      ...> |> #{@gql}.field(:node, args: %{id: "123"})
      ...> |> #{@gql}.field(:id, path: [:node])
      ...> |> #{@gql}.fragment(type: nil, path: [:node])
      ...> |> #{@gql}.field(:__typename, path: [:node, {nil, type: nil}])
      ...> |> to_string()
      \"\"\"
      query {
        node(id: "123") {
          id
          ... {
            __typename
          }
        }
      }
      \"\"\"

  The `fields` option allows you to specify subfields directly within the inline fragment:

      iex> #{@gql}.new()
      ...> |> #{@gql}.field(:search, args: %{term: "elixir"})
      ...> |> #{@gql}.fragment(type: :User, path: [:search], fields: [:name, :email])
      ...> |> #{@gql}.fragment(type: :Post, path: [:search], fields: [:title, :content])
      ...> |> to_string()
      \"\"\"
      query {
        search(term: "elixir") {
          ... on User {
            name
            email
          }
          ... on Post {
            title
            content
          }
        }
      }
      \"\"\"

  Subfield definitions support the same options as the main field definition,
  including `alias` and `args`:

      iex> #{@gql}.new()
      ...> |> #{@gql}.field(:search)
      ...> |> #{@gql}.fragment(type: :User, path: [:search], fields: [:id, {:name, alias: "fullName"}])
      ...> |> to_string()
      \"\"\"
      query {
        search {
          ... on User {
            id
            fullName: name
          }
        }
      }
      \"\"\"

  """
  def fragment(doc, opts \\ []) do
    doc = parse(doc)

    cond do
      # Named fragment mode: name and type are provided
      Keyword.has_key?(opts, :name) ->
        name = Keyword.fetch!(opts, :name)
        type = Keyword.fetch!(opts, :type)

        fragment = %Fragment{
          name: to_string(name),
          type_condition: %NamedType{name: to_string(type)},
          directives: [],
          selection_set: %SelectionSet{selections: []}
        }

        %{doc | definitions: doc.definitions ++ [fragment]}

      # Inline fragment mode: path is provided
      Keyword.has_key?(opts, :path) ->
        path = Keyword.get(opts, :path, []) |> List.wrap()
        type = Keyword.get(opts, :type)
        subfields = Keyword.get(opts, :fields, [])

        type_condition = type && %NamedType{name: to_string(type)}

        inline_fragment = %InlineFragment{
          type_condition: type_condition,
          directives: [],
          selection_set: %SelectionSet{selections: []}
        }

        optic = build_field_optic(path, :selections)
        doc = update_in(doc, optic, fn selection_list -> (selection_list || []) ++ [inline_fragment] end)

        subfield_path = path ++ [{nil, type: type}]

        Enum.reduce(subfields, doc, fn subfield_def, acc_doc ->
          add_subfield(acc_doc, subfield_def, subfield_path)
        end)

      true ->
        raise ArgumentError,
              "fragment/2 requires either :name and :type options (for named fragments) or :path option (for inline fragments)"
    end
  end

  @doc """
  Deletes a fragment from the document by its name.

  ## Examples

  Removing a fragment:

      iex> "query { user { id } }"
      ...> |> #{@gql}.fragment(name: :UserFields, type: :User)
      ...> |> #{@gql}.fragment(name: :PostInfo, type: :Post)
      ...> |> #{@gql}.remove_fragment(:UserFields)
      ...> |> #{@gql}.field("x", path: :PostInfo)
      ...> |> to_string() |> String.replace(~r/\\n[ ]*\\n/m, "\\n")
      \"\"\"
      query {
        user {
          id
        }
      }
      fragment PostInfo on Post {
        x
      }
      \"\"\"

  Removing a non-existent fragment does nothing:

      iex> "query { user { id } }"
      ...> |> #{@gql}.fragment(name: :UserFields, type: :User)
      ...> |> #{@gql}.remove_fragment(:NonExistent)
      ...> |> #{@gql}.field("x", path: :UserFields)
      ...> |> to_string() |> String.replace(~r/\\n[ ]*\\n/m, "\\n")
      \"\"\"
      query {
        user {
          id
        }
      }
      fragment UserFields on User {
        x
      }
      \"\"\"

  """
  def remove_fragment(doc, name) do
    doc = parse(doc)
    name = to_string(name)

    %{
      doc
      | definitions:
          Enum.reject(doc.definitions, fn
            %Fragment{name: ^name} -> true
            _ -> false
          end)
    }
  end

  @doc """
  Spreads a named fragment into a selection set at the specified path.

  Fragment spreads allow you to reference and reuse a named fragment definition
  within your query. The fragment must be defined elsewhere in the document using
  the `fragment/3` function.

  ## Examples

  Spreading a fragment at the root level:

      iex> #{@gql}.new()
      ...> |> #{@gql}.fragment(name: :UserFields, type: :User)
      ...> |> #{@gql}.field(:name, path: [:UserFields])
      ...> |> #{@gql}.field(:email, path: [:UserFields])
      ...> |> #{@gql}.field(:user)
      ...> |> #{@gql}.spread_fragment(:UserFields, path: [:user])
      ...> |> to_string() |> String.replace("\\n\\n", "\\n")
      \"\"\"
      query {
        user {
          ...UserFields
        }
      }
      fragment UserFields on User {
        name
        email
      }
      \"\"\"

  Spreading a fragment in a nested field:

      iex> #{@gql}.new()
      ...> |> #{@gql}.fragment(name: :ContactInfo, type: :User)
      ...> |> #{@gql}.field(:email, path: [:ContactInfo])
      ...> |> #{@gql}.field(:phone, path: [:ContactInfo])
      ...> |> #{@gql}.field(:organization)
      ...> |> #{@gql}.field(:users, path: [:organization])
      ...> |> #{@gql}.spread_fragment(:ContactInfo, path: [:organization, :users])
      ...> |> to_string() |> String.replace("\\n\\n", "\\n")
      \"\"\"
      query {
        organization {
          users {
            ...ContactInfo
          }
        }
      }
      fragment ContactInfo on User {
        email
        phone
      }
      \"\"\"

  """
  def spread_fragment(doc, name, opts \\ []) do
    doc = parse(doc)
    name = to_string(name)
    path = Keyword.get(opts, :path, []) |> List.wrap()

    fragment_spread = %FragmentSpread{
      name: name,
      directives: []
    }

    # Check if the first path element is a fragment name
    {target_filter, field_path} =
      case path do
        [first | rest] ->
          first_str = to_string(first)
          # Check if this matches a fragment definition
          has_fragment =
            Enum.any?(doc.definitions, fn
              %Fragment{name: ^first_str} -> true
              _ -> false
            end)

          if has_fragment do
            # Target only this fragment, and don't navigate into it as a field
            {Access.filter(&match?(%Fragment{name: ^first_str}, &1)), rest}
          else
            # Target only operation definitions, use full path
            {Access.filter(&match?(%OperationDefinition{}, &1)), path}
          end

        [] ->
          # No path, target operation definitions
          {Access.filter(&match?(%OperationDefinition{}, &1)), []}
      end

    optic =
      [
        access_key(:definitions, nil, []),
        target_filter,
        for path_element <- field_path do
          build_path_navigation(path_element)
        end,
        access_key(:selection_set, nil, %SelectionSet{}),
        Access.key(:selections, [])
      ]
      |> List.flatten()

    update_in(doc, optic, fn selection_list -> (selection_list || []) ++ [fragment_spread] end)
  end

  @doc """
  Inlines all fragment spreads into the main selection set for simplified document structure.

  This function replaces all fragment spreads (`...FragmentName`) with the actual fields
  from the fragment definition, then removes the fragment definitions from the document.
  This is useful when you want to convert a document with named fragments into a single
  inline query without separate fragment definitions.

  ## Examples

  Inlining a simple fragment:

      iex> #{@gql}.new()
      ...> |> #{@gql}.fragment(name: :UserFields, type: :User)
      ...> |> #{@gql}.field(:name, path: [:UserFields])
      ...> |> #{@gql}.field(:email, path: [:UserFields])
      ...> |> #{@gql}.field(:user)
      ...> |> #{@gql}.spread_fragment(:UserFields, path: [:user])
      ...> |> #{@gql}.inline_fragments()
      ...> |> to_string()
      \"\"\"
      query {
        user {
          name
          email
        }
      }
      \"\"\"

  Inlining multiple fragments:

      iex> #{@gql}.new()
      ...> |> #{@gql}.fragment(name: :BasicInfo, type: :User)
      ...> |> #{@gql}.field(:id, path: [:BasicInfo])
      ...> |> #{@gql}.field(:name, path: [:BasicInfo])
      ...> |> #{@gql}.fragment(name: :ContactInfo, type: :User)
      ...> |> #{@gql}.field(:email, path: [:ContactInfo])
      ...> |> #{@gql}.field(:phone, path: [:ContactInfo])
      ...> |> #{@gql}.field(:user)
      ...> |> #{@gql}.spread_fragment(:BasicInfo, path: [:user])
      ...> |> #{@gql}.spread_fragment(:ContactInfo, path: [:user])
      ...> |> #{@gql}.inline_fragments()
      ...> |> to_string()
      \"\"\"
      query {
        user {
          id
          name
          email
          phone
        }
      }
      \"\"\"

  """
  def inline_fragments(doc) do
    doc = parse(doc)

    # Build a map of fragment name -> fragment definition for quick lookup
    fragment_map =
      doc.definitions
      |> Enum.filter(&match?(%Fragment{}, &1))
      |> Map.new(fn %Fragment{name: name} = fragment -> {name, fragment} end)

    # Process all operation definitions to replace fragment spreads
    inlined_definitions =
      for definition <- doc.definitions do
        case definition do
          %OperationDefinition{} = op_def ->
            %{op_def | selection_set: inline_selection_set(op_def.selection_set, fragment_map)}

          %Fragment{} ->
            # Skip fragment definitions - they'll be removed
            nil
        end
      end
      |> Enum.reject(&is_nil/1)

    %{doc | definitions: inlined_definitions}
  end

  # Recursively inline fragment spreads in a selection set
  defp inline_selection_set(nil, _fragment_map), do: nil

  defp inline_selection_set(%SelectionSet{selections: selections} = selection_set, fragment_map) do
    inlined_selections =
      selections
      |> Enum.flat_map(fn
        %FragmentSpread{name: name} ->
          # Replace fragment spread with the fragment's selections
          case Map.get(fragment_map, name) do
            %Fragment{selection_set: fragment_selection_set} ->
              # Recursively inline any nested fragment spreads
              inlined_fragment_set = inline_selection_set(fragment_selection_set, fragment_map)
              inlined_fragment_set.selections

            nil ->
              # Fragment not found, keep the spread as-is
              [%FragmentSpread{name: name}]
          end

        %Field{selection_set: field_selection_set} = field ->
          # Recursively process nested selections in fields
          [%{field | selection_set: inline_selection_set(field_selection_set, fragment_map)}]

        %InlineFragment{selection_set: inline_fragment_set} = inline_fragment ->
          # Recursively process selections in inline fragments
          [
            %{
              inline_fragment
              | selection_set: inline_selection_set(inline_fragment_set, fragment_map)
            }
          ]

        other ->
          [other]
      end)

    %{selection_set | selections: inlined_selections}
  end

  @doc """
  Automatically injects the __typename field into all object selections.

    iex> \"""
    ...>   query {
    ...>     apple {
    ...>       foo
    ...>       bar {
    ...>         baz
    ...>       }
    ...>     }
    ...>   }
    ...> \"""
    ...> |> #{@gql}.inject_typenames()
    ...> |> to_string()
    \"\"\"
    query {
      apple {
        foo
        bar {
          baz
          __typename
        }
        __typename
      }
      __typename
    }
    \"\"\"

  """
  def inject_typenames(doc) do
    for path <- paths(doc), reduce: doc do
      doc -> field(doc, "__typename", path: path)
    end
  end

  @doc """
  Inlines the given variables into the document.

      iex> "query Q($id: ID!) { get(id: $id) { name } }"
      ...> |> #{@gql}.inline_valriables(%{id: 42})
      ...> |> to_string()
      \"\"\"
      query Q {
        get(id: 42) {
          name
        }
      }
      \"\"\"

  """
  def inline_valriables(doc, %{} = args) do
    for {variable, value} <- args, reduce: doc do
      doc ->
        doc
        |> remove_variable(variable)
        |> substitute_variable(variable, value)
    end
  end

  @doc """
  Merges two GraphQL documents by combining their variables and fields.

  When operation types match (both query, mutation, or subscription), the result
  is a single document containing:
  - All variable definitions from both documents (deduplicated by name)
  - All top-level fields from both documents (deduplicated by name and arguments)

  When operation types don't match, the result contains separate definitions
  for each operation type.

  ## Examples

  Merging documents with matching operation types:

      iex> doc1 = "query { user { id } }"
      iex> doc2 = "query { posts { title } }"
      iex> #{@gql}.merge(doc1, doc2) |> to_string()
      \"\"\"
      query {
        user {
          id
        }
        posts {
          title
        }
      }
      \"\"\"

  Merging documents with variables (deduplicates by name):

      iex> doc1 = "query Q($id: ID!) { user(id: $id) { name } }"
      iex> doc2 = "query Q($id: ID!) { posts { title } }"
      iex> #{@gql}.merge(doc1, doc2) |> to_string()
      \"\"\"
      query Q($id: ID!) {
        user(id: $id) {
          name
        }
        posts {
          title
        }
      }
      \"\"\"

  Deduplicating identical fields:

      iex> doc1 = "query { user { id } }"
      iex> doc2 = "query { user { name } }"
      iex> #{@gql}.merge(doc1, doc2) |> to_string()
      \"\"\"
      query {
        user {
          id
          name
        }
      }
      \"\"\"

  Merging documents with different operation types:

      iex> doc1 = "query { user { id } }"
      iex> doc2 = "mutation { createUser { id } }"
      iex> #{@gql}.merge(doc1, doc2)
      ...> |> to_string() |> String.replace("\\n\\n", "\\n")
      \"\"\"
      query {
        user {
          id
        }
      }
      mutation {
        createUser {
          id
        }
      }
      \"\"\"

  """
  def merge(doc, other) do
    {doc, other} = {parse(doc), parse(other)}

    grouped = Enum.group_by(doc.definitions ++ other.definitions, & &1.operation)

    %{
      doc
      | definitions:
          for {_operation, definitions} <- grouped do
            merge_definitions(definitions)
          end
    }
  end

  ### Helpers

  # Build a common optic for navigating to a field property (arguments, directives, selections)
  defp build_field_optic(path, target_key) do
    [
      access_key(:definitions, nil, []),
      Access.all(),
      for path_element <- path do
        {name, alias_name, args} = parse_path_element(path_element)

        field = %Field{
          name: name,
          alias: alias_name && to_string(alias_name),
          arguments: arguments(args)
        }

        [
          access_key(:selection_set, nil, %SelectionSet{}),
          access_key(:selections, [], [field]),
          Access.filter(fn selection ->
            alias_val = Map.get(selection, :alias)
            name_val = Map.get(selection, :name)
            # If has alias, only match on alias; otherwise match on name
            if alias_val, do: alias_val == name, else: name_val == name
          end)
        ]
      end,
      case target_key do
        :selections -> [access_key(:selection_set, nil, %SelectionSet{}), Access.key(:selections, [])]
        _ -> Access.key(target_key, [])
      end
    ]
    |> List.flatten()
  end

  defp merge_definitions([single]), do: single

  defp merge_definitions(definitions) do
    # Take the first definition as base
    [base | _rest] = definitions

    # Merge all variable definitions (deduplicate by variable name)
    all_variables =
      Enum.flat_map(definitions, & &1.variable_definitions)
      |> Enum.uniq_by(fn %{variable: %{name: name}} -> name end)

    # Merge all top-level fields (deduplicate by name and arguments)
    all_selections =
      Enum.flat_map(definitions, fn definition ->
        definition.selection_set.selections
      end)
      |> deduplicate_fields()

    # Build merged definition
    %{
      base
      | variable_definitions: all_variables,
        selection_set: %{base.selection_set | selections: all_selections}
    }
  end

  defp deduplicate_fields(fields) do
    # Two fields are considered identical if they have the same:
    # - name (or alias if present)
    # - arguments (both names and values)
    # We preserve order by processing fields left-to-right
    {result, _seen} =
      Enum.reduce(fields, {[], %{}}, fn field, {acc, seen} ->
        field_identifier = Map.get(field, :alias) || Map.get(field, :name)

        args_signature =
          field.arguments
          |> Enum.map(fn arg -> {arg.name, inspect(arg.value)} end)
          |> Enum.sort()

        key = {field_identifier, args_signature}

        case Map.get(seen, key) do
          nil ->
            # First time seeing this field, add it to result
            {acc ++ [field], Map.put(seen, key, length(acc))}

          index ->
            # We've seen this field before, merge subfields
            existing_field = Enum.at(acc, index)

            # Collect all subfield selections
            existing_subfields =
              case existing_field.selection_set do
                nil -> []
                %{selections: selections} -> selections
              end

            new_subfields =
              case field.selection_set do
                nil -> []
                %{selections: selections} -> selections
              end

            # Recursively deduplicate the merged subfields
            merged_subfields = deduplicate_fields(existing_subfields ++ new_subfields)

            # Update the field at the original position
            updated_field =
              case merged_subfields do
                [] ->
                  existing_field

                _ ->
                  %{existing_field | selection_set: %SelectionSet{selections: merged_subfields}}
              end

            {List.replace_at(acc, index, updated_field), seen}
        end
      end)

    result
  end

  defp wrap_value(nil), do: {nil, nil}
  defp wrap_value(:null), do: {"NullValue", %NullValue{}}
  defp wrap_value(int) when is_integer(int), do: {"Integer", %IntValue{value: int}}
  defp wrap_value(float) when is_float(float), do: {"Float", %FloatValue{value: float}}
  defp wrap_value(bool) when is_boolean(bool), do: {"Boolean", %BooleanValue{value: bool}}
  defp wrap_value(atom) when is_atom(atom), do: {nil, %EnumValue{value: atom}}
  defp wrap_value("$" <> name), do: {nil, %Variable{name: name}}
  defp wrap_value("" <> string), do: {"String", %StringValue{value: string}}

  defp wrap_value(%{} = map) do
    {nil, %ObjectValue{fields:
      for {name, value} <- map do
        {_, value} = wrap_value(value)
        %ObjectField{name: to_string(name), value: value}
      end
    }}
  end

  defp wrap_value(list) when is_list(list) do
    {types, values} = Enum.unzip(Enum.map(list, &wrap_value(&1)))
    [type] = Enum.uniq(types)
    {"[#{type}!]", %ListValue{values: values}}
  end

  defp to_type(atom) when is_atom(atom) do
    first_grapheme = atom |> inspect() |> String.graphemes() |> List.first()

    if first_grapheme == ":" do
      to_string(atom)
    else
      inspect(atom)
    end
  end

  defp to_type(str) when is_binary(str), do: str

  defp access_key(key, src, default) do
    fn
      :get, data, next ->
        next.(substitute(Map.get(data, key, default), src, default))

      :get_and_update, data, next ->
        value = substitute(Map.get(data, key, default), src, default)

        case next.(value) do
          {get, update} -> {get, Map.put(data, key, update)}
          :pop -> {value, Map.delete(data, key)}
        end
    end
  end

  def all2(default) do
    all = Access.all()

    fn
      op, [], next ->
        all.(op, [default], next)

      op, data, next ->
        all.(op, data, next)
    end
  end

  def all do
    &all/3
  end

  defp all(:get, data, next) when is_list(data) do
    Enum.map(data, next)
  end

  defp all(:get_and_update, data, next) when is_list(data) do
    all(data, next, _gets = [], _updates = [])
  end

  defp all(_op, data, _next) do
    raise "Access.all/0 expected a list, got: #{inspect(data)}"
  end

  defp all([head | rest], next, gets, updates) do
    case next.(head) do
      {get, update} -> all(rest, next, [get | gets], [update | updates])
      :pop -> all(rest, next, [head | gets], updates)
    end
  end

  defp all([], _next, gets, updates) do
    {:lists.reverse(gets), :lists.reverse(updates)}
  end

  defp substitute(value, src, dst) do
    if value == src, do: dst, else: value
  end

  defp substitute_variable(doc, variable, value) do
    doc = parse(doc)
    variable_name = to_string(variable)
    {_type, wrapped_value} = wrap_value(value)

    %{
      doc
      | definitions:
          for definition <- doc.definitions do
            %{
              definition
              | selection_set:
                  substitute_in_selection_set(
                    definition.selection_set,
                    variable_name,
                    wrapped_value
                  )
            }
          end
    }
  end

  defp substitute_in_selection_set(nil, _variable_name, _value), do: nil

  defp substitute_in_selection_set(
         %SelectionSet{selections: selections} = selection_set,
         variable_name,
         value
       ) do
    %{
      selection_set
      | selections:
          for selection <- selections do
            substitute_in_field(selection, variable_name, value)
          end
    }
  end

  defp substitute_in_field(%Field{} = field, variable_name, value) do
    %{
      field
      | arguments: substitute_in_arguments(field.arguments, variable_name, value),
        selection_set: substitute_in_selection_set(field.selection_set, variable_name, value)
    }
  end

  defp substitute_in_arguments(arguments, variable_name, value) do
    for argument <- arguments do
      %{argument | value: substitute_in_value(argument.value, variable_name, value)}
    end
  end

  defp substitute_in_value(%Variable{name: name}, variable_name, value)
       when name == variable_name do
    value
  end

  defp substitute_in_value(%ListValue{values: values} = list_value, variable_name, value) do
    %{list_value | values: Enum.map(values, &substitute_in_value(&1, variable_name, value))}
  end

  defp substitute_in_value(other_value, _variable_name, _value), do: other_value

  defp arguments(args) do
    for {name, value} <- args do
      {_type, value} = wrap_value(value)
      %Argument{name: to_string(name), value: value}
    end
  end

  defp paths(doc) do
    doc = parse(doc)

    doc.definitions
    |> Enum.flat_map(fn definition ->
      _paths(definition.selection_set)
    end)
    |> Enum.uniq()
  end

  defp _paths(nil), do: []

  defp _paths(%SelectionSet{selections: selections}) do
    nested_paths =
      for field <- selections, field.selection_set != nil do
        field_name = Map.get(field, :alias) || Map.get(field, :name)

        for path <- _paths(field.selection_set) do
          [field_name | path]
        end
      end
      |> flatten_just_one_level()

    [[] | nested_paths]
  end

  defp flatten_just_one_level(list), do: Enum.flat_map(list, &Function.identity/1)
end

defimpl String.Chars, for: Document do
  @doc """
  Serializes the abstract document structure into a GraphQL query string.
  """
  def to_string(doc), do: inspect(doc, limit: :infinity, pretty: true, structs: true)
end

defimpl List.Chars, for: Document do
  def to_charlist(doc) do
    doc
    |> to_string()
    |> Kernel.to_charlist()
  end
end
