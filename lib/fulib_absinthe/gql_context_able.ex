defmodule FulibAbsinthe.GQLContextAble do
  defmacro __using__(opts \\ []) do
    quote do
      @behaviour Plug

      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :plug_module, accumulate: false)
      Module.put_attribute(__MODULE__, :plug_module, opts[:plug_module])

      Module.eval_quoted(
        __MODULE__,
        quote do
          def init(opts), do: opts

          def call(conn, _) do
            @plug_module.put_options(conn, context: conn)
          end
        end
      )
    end
  end
end
