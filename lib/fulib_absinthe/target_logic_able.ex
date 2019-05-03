defmodule FulibAbsinthe.TargetLogicAble do
  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      target_module_values =
        opts[:target_modules_original]
        |> Enum.map(fn {name, {value, module}} ->
          {value, {value, name, module}}
        end)
        |> Map.new()

      target_module_names =
        opts[:target_modules_original]
        |> Enum.map(fn {name, {value, module}} ->
          {name, {value, name, module}}
        end)
        |> Map.new()

      target_modules =
        opts[:target_modules_original]
        |> Enum.map(fn {name, {value, module}} ->
          {module, {value, name, module}}
        end)
        |> Map.new()

      Module.register_attribute(__MODULE__, :target_modules_original, accumulate: false)
      Module.put_attribute(__MODULE__, :target_modules_original, opts[:target_modules_original])

      Module.register_attribute(__MODULE__, :target_module_values, accumulate: false)
      Module.put_attribute(__MODULE__, :target_module_values, target_module_values)

      Module.register_attribute(__MODULE__, :target_module_names, accumulate: false)
      Module.put_attribute(__MODULE__, :target_module_names, target_module_names)

      Module.register_attribute(__MODULE__, :target_modules, accumulate: false)
      Module.put_attribute(__MODULE__, :target_modules, target_modules)

      Module.eval_quoted(
        __MODULE__,
        quote do
          def target_modules, do: @target_modules

          def target_module_names, do: @target_module_names

          def target_module_values, do: @target_module_values
        end
      )
    end
  end
end
