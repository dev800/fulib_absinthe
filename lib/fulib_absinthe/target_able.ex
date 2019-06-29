defmodule FulibAbsinthe.TargetAble do
  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :engine_module, accumulate: false)
      Module.put_attribute(__MODULE__, :engine_module, opts[:engine_module])

      Module.eval_quoted(
        __MODULE__,
        quote do
          def get_polymorphic() do
            Module.concat(@engine_module, "TargetLogic").get_polymorphic_by_module(__MODULE__)
          end

          def get_polymorphic_key(source) do
            [
              source.__struct__.get_polymorphic_value(),
              source.id
            ]
            |> Enum.join("_")
          end

          def get_polymorphic_name() do
            case get_polymorphic() do
              {_value, name, _module} ->
                name

              _ ->
                nil
            end
          end

          def get_polymorphic_value() do
            case get_polymorphic() do
              {value, _name, _module} ->
                value

              _ ->
                nil
            end
          end
        end
      )
    end
  end
end
