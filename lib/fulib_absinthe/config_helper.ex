defmodule FulibAbsinthe.ConfigHelper do
  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :app_name, accumulate: false)
      Module.put_attribute(__MODULE__, :app_name, opts[:app_name])

      Module.put_attribute(
        __MODULE__,
        :env_app_name,
        opts[:app_name] |> Fulib.to_s() |> String.upcase()
      )

      Module.eval_quoted(
        __MODULE__,
        quote do
          def grpc_urls do
            System.get_env("#{@env_app_name}_GRPC_URLS")
            |> Kernel.||(Application.get_env(@app_name, :grpc_urls))
            |> case do
              nil ->
                ["#{grpc_ip() |> Tuple.to_list() |> Enum.join(".")}:#{grpc_port()}"]

              urls ->
                urls
                |> Fulib.to_s()
                |> String.split(",", trim: true)
            end
          end

          def grpc_url() do
            grpc_urls() |> Fulib.sample()
          end

          def grpc_port() do
            (System.get_env("#{@env_app_name}_GRPC_PORT") ||
               Application.get_env(@app_name, :grpc_port))
            |> _normalize_port()
          end

          def grpc_ip() do
            (System.get_env("#{@env_app_name}_GRPC_IP") ||
               Application.get_env(@app_name, :grpc_ip))
            |> _normalize_ip()
          end

          def plug_port() do
            (System.get_env("#{@env_app_name}_PLUG_PORT") ||
               Application.get_env(@app_name, :plug_port))
            |> _normalize_port()
          end

          def plug_ip() do
            (System.get_env("#{@env_app_name}_PLUG_IP") ||
               Application.get_env(@app_name, :plug_ip))
            |> _normalize_ip()
          end

          def plug_urls() do
            System.get_env("#{@env_app_name}_PLUG_URLS")
            |> Kernel.||(Application.get_env(@app_name, :plug_urls))
            |> case do
              nil ->
                ["http://#{plug_ip() |> Tuple.to_list() |> Enum.join(".")}:#{plug_port()}"]

              urls ->
                urls
                |> Fulib.to_s()
                |> String.split(",", trim: true)
            end
          end

          def plug_url() do
            plug_urls() |> Fulib.sample()
          end

          defp _normalize_port(port) when is_binary(port) do
            port |> String.to_integer()
          end

          defp _normalize_port(nil), do: nil

          defp _normalize_port(port), do: port

          defp _normalize_ip({a, b, c, d}), do: {a, b, c, d}

          defp _normalize_ip(ip) when is_binary(ip) do
            ip
            |> String.split(".")
            |> Enum.map(fn v -> String.to_integer(v) end)
            |> List.to_tuple()
          end

          defp _normalize_ip(nil), do: {0, 0, 0, 0}
        end
      )
    end
  end
end
