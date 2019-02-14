defmodule FulibAbsinthe.ClientAble do
  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :grpc_stub, accumulate: false)
      Module.put_attribute(__MODULE__, :grpc_stub, opts[:grpc_stub])

      Module.register_attribute(__MODULE__, :grpc_request, accumulate: false)
      Module.put_attribute(__MODULE__, :grpc_request, opts[:grpc_request])

      Module.register_attribute(__MODULE__, :grpc_response, accumulate: false)
      Module.put_attribute(__MODULE__, :grpc_response, opts[:grpc_response])

      Module.register_attribute(__MODULE__, :config, accumulate: false)
      Module.put_attribute(__MODULE__, :config, opts[:config])

      Module.register_attribute(__MODULE__, :service_name, accumulate: false)
      Module.put_attribute(__MODULE__, :service_name, opts[:service_name])

      Module.eval_quoted(
        __MODULE__,
        quote do
          def grpc_urls, do: @config.grpc_urls

          def grpc_stub, do: @grpc_stub

          def grpc_request, do: @grpc_request

          def grpc_response, do: @grpc_response

          def plug_urls, do: @config.plug_urls

          def service_name, do: @service_name

          def http_post(fn_name, query, variables \\ %{}, opts \\ []) do
            url = opts[:url] || plug_urls() |> Fulib.to_array() |> Fulib.sample()

            "#{url}/#{@service_name}/#{fn_name}"
            |> HTTPoison.post(
              Jason.encode!(%{
                query: query,
                variables: variables
              }),
              [
                {"content-type", "application/json"}
              ]
            )
            |> case do
              {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
                body |> Jason.decode()

              {:error, %HTTPoison.Error{reason: reason}} ->
                {:error, reason}

              {:ok, %HTTPoison.Response{body: body, status_code: status_code}} ->
                body
                |> Jason.decode()
                |> case do
                  {:ok, data} ->
                    {:error, data}

                  _ ->
                    {:error, "status code #{status_code}"}
                end
            end
          end

          @doc """
          执行grpc方法

          ## Params

          ### opts

          * `:url` GRPC的域名，不传则取@grpc_urls中的一个

          ## Return

          ### OK
          {:ok, %WordService.GQLResponse{body: ..., message: message, status: "ok"}}

          ### Error
          {:error, "timeout when waiting for server"}
          """
          def grpc(fn_name, query, variables \\ %{}, opts \\ []) do
            try do
              opts
              |> grpc_channel()
              |> case do
                {:ok, channel} ->
                  @grpc_stub
                  |> apply(fn_name, [
                    channel,
                    @grpc_request.new(query: query, variables: Jason.encode!(variables || "{}"))
                  ])
                  |> case do
                    {:ok, %{status: "ok", body: body} = response} ->
                      response |> Map.put(:body, Jason.decode!(body))

                    other ->
                      other
                  end

                other ->
                  other
              end
            catch
              :error, %GRPC.RPCError{message: message} ->
                {:error, message}

              _, _ ->
                {:error, "GRPC server error"}
            end
          end

          def grpc_channel(opts \\ []) do
            cache_key = :"#{__MODULE__}:grpc_channel"
            url = opts[:url] || grpc_urls() |> Fulib.to_array() |> Fulib.sample()

            cache_key
            |> Fulib.LocalCache.get()
            |> case do
              %GRPC.Channel{adapter_payload: %{conn_pid: conn_pid}} = channel ->
                if Process.alive?(conn_pid) do
                  {:ok, channel}
                else
                  url |> grpc_connect()
                end

              _ ->
                url |> grpc_connect()
            end
            |> case do
              {:ok, channel} ->
                Fulib.LocalCache.set(cache_key, channel)
                {:ok, channel}

              other ->
                other
            end
          end

          def grpc_connect(url) do
            url
            |> GRPC.Stub.connect()
            |> case do
              {:ok, channel} ->
                {:ok, channel}

              {:error, reason} ->
                raise GRPC.RPCError, status: GRPC.Status.internal(), message: reason
            end
          end
        end
      )
    end
  end
end
