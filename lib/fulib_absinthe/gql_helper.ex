defmodule FulibAbsinthe.GQLHelper do
  def run(query, opts, schema) do
    conn = Fulib.get(opts, :conn, %Plug.Conn{}, %Plug.Conn{})

    variables =
      Fulib.get(opts, :variables, %{}, %{})
      |> Fulib.Map.recase_keys_deep!(case: :camel)
      |> Fulib.Map.string_keys_deep!()

    opts = opts |> Fulib.put(:context, conn) |> Fulib.put(:variables, variables)
    query |> Absinthe.run(schema, opts)
  end
end
