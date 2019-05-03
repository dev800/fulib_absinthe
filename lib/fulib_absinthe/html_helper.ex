defmodule FulibAbsinthe.HTMLHelper do
  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :routers, accumulate: false)
      Module.put_attribute(__MODULE__, :routers, opts[:routers])

      Module.register_attribute(__MODULE__, :endport, accumulate: false)
      Module.put_attribute(__MODULE__, :endport, opts[:endport])

      Module.register_attribute(__MODULE__, :app_name, accumulate: false)
      Module.put_attribute(__MODULE__, :app_name, opts[:app_name])

      Module.eval_quoted(
        __MODULE__,
        quote do
          def static_path(endpoint, path) do
            case Mix.env() do
              :dev ->
                @routers.static_path(endpoint, path)

              _ ->
                url =
                  Fulib.Process.fetch(:"webpack_manifest@#{@app_name}", fn ->
                    Application.get_env(@app_name, @endport)
                    |> Keyword.fetch!(:webpack_manifest)
                    |> File.read!()
                    |> Jason.decode!()
                  end)
                  |> get_in(decode_path(path))
                  |> Kernel.||(path)

                @routers.static_path(endpoint, url)
            end
          end

          defp decode_path(path) do
            ~r/\/?(.*)\/(.*)\..*/
            |> Regex.scan(path)
            |> case do
              [[_, ext, name]] ->
                [name, ext]

              _ ->
                []
            end
          end
        end
      )
    end
  end
end
