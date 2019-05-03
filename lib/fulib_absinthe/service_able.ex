defmodule FulibAbsinthe.ServiceAble do
  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :db_table_prefix, accumulate: false)
      Module.put_attribute(__MODULE__, :db_table_prefix, opts[:db_table_prefix])

      Module.eval_quoted(
        __MODULE__,
        quote do
          def db_table_name(name, type \\ :atom)

          def db_table_name(name, :atom) do
            db_table_name(name, :string) |> Fulib.to_atom()
          end

          def db_table_name(name, :string) do
            "#{@db_table_prefix}#{name}"
          end
        end
      )
    end
  end
end
