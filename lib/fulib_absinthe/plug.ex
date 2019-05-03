defmodule FulibAbsinthe.Plug do
  def put_options(%Plug.Conn{private: %{absinthe: absinthe}} = conn, opts) do
    opts = Map.merge(absinthe, Enum.into(opts, %{}))
    Plug.Conn.put_private(conn, :absinthe, opts)
  end

  def put_options(conn, opts) do
    Plug.Conn.put_private(conn, :absinthe, Enum.into(opts, %{}))
  end

  def put_context(conn, key, value) do
    put_options(conn, %{context: conn |> get_context() |> Fulib.put(key, value)})
  end

  def get_context(conn) do
    conn.private |> Fulib.get(:absinthe) |> Fulib.get(:context) |> Kernel.||(%{})
  end

  def get_context(conn, key) do
    conn |> get_context() |> Fulib.get(key)
  end
end
