defmodule FulibAbsinthe.PlugAble do
  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour Plug
      import Plug.Conn
      require Logger

      alias Absinthe.Plug.Request

      @raw_options [:analyze_complexity, :max_complexity]

      @type function_name :: atom

      @type opts :: [
              schema: module,
              adapter: module,
              context: map,
              json_codec: module | {module, Keyword.t()},
              pipeline: {module, atom},
              no_query_message: String.t(),
              document_providers:
                [Absinthe.Plug.DocumentProvider.t(), ...]
                | Absinthe.Plug.DocumentProvider.t()
                | {module, atom},
              analyze_complexity: boolean,
              max_complexity: non_neg_integer | :infinity,
              serializer: module | {module, Keyword.t()},
              content_type: String.t(),
              before_send: {module, atom},
              log_level: Logger.level()
            ]

      Module.eval_quoted(
        __MODULE__,
        quote do
          import Plug.Conn

          @doc """
          Serve an Absinthe GraphQL schema with the specified options.

          ## Options

          See the documentation for the `Absinthe.Plug.opts` type for details on the available options.
          """
          @spec init(opts :: opts) :: map
          def init(opts) do
            adapter = Keyword.get(opts, :adapter, Absinthe.Adapter.LanguageConventions)
            context = Keyword.get(opts, :context, %{})

            no_query_message = Keyword.get(opts, :no_query_message, "No query document supplied")

            pipeline = Keyword.get(opts, :pipeline, {__MODULE__, :default_pipeline})

            document_providers =
              Keyword.get(opts, :document_providers, {__MODULE__, :default_document_providers})

            json_codec =
              case Keyword.get(opts, :json_codec, Poison) do
                module when is_atom(module) -> %{module: module, opts: []}
                other -> other
              end

            serializer =
              case Keyword.get(opts, :serializer, json_codec) do
                module when is_atom(module) -> %{module: module, opts: []}
                {mod, opts} -> %{module: mod, opts: opts}
                other -> other
              end

            content_type = Keyword.get(opts, :content_type, "application/json")

            schema_mod = opts |> get_schema

            raw_options = Keyword.take(opts, @raw_options)
            log_level = Keyword.get(opts, :log_level, :debug)

            pubsub = Keyword.get(opts, :pubsub, nil)

            before_send = Keyword.get(opts, :before_send)

            %{
              adapter: adapter,
              context: context,
              document_providers: document_providers,
              json_codec: json_codec,
              no_query_message: no_query_message,
              pipeline: pipeline,
              raw_options: raw_options,
              schema_mod: schema_mod,
              serializer: serializer,
              content_type: content_type,
              log_level: log_level,
              pubsub: pubsub,
              before_send: before_send
            }
          end

          defp get_schema(opts) do
            default = Application.get_env(:absinthe, :schema)
            schema = Keyword.get(opts, :schema, default)

            try do
              Absinthe.Schema.types(schema)
            rescue
              UndefinedFunctionError ->
                raise ArgumentError,
                      "The supplied schema: #{inspect(schema)} is not a valid Absinthe Schema"
            end

            schema
          end

          @doc false
          def apply_before_send(conn, bps, %{before_send: {mod, fun}}) do
            Enum.reduce(bps, conn, fn bp, conn ->
              apply(mod, fun, [conn, bp])
            end)
          end

          def apply_before_send(conn, _, _) do
            conn
          end

          @doc """
          Parses, validates, resolves, and executes the given Graphql Document
          """
          @spec call(Plug.Conn.t(), map) :: Plug.Conn.t() | no_return
          def call(conn, config) do
            config = update_config(conn, config)
            {conn, result} = conn |> execute(config)

            case result do
              {:input_error, msg} ->
                conn
                |> encode(400, error_result(msg), config)

              {:ok, %{"subscribed" => topic}} ->
                conn
                |> subscribe(topic, config)

              {:ok, %{data: _} = result} ->
                conn
                |> encode(200, result, config)

              {:ok, %{errors: _} = result} ->
                conn
                |> encode(200, result, config)

              {:ok, result} when is_list(result) ->
                conn
                |> encode(200, result, config)

              {:error, {:http_method, text}, _} ->
                conn
                |> encode(405, error_result(text), config)

              {:error, error, _} when is_binary(error) ->
                conn
                |> encode(500, error_result(error), config)
            end
          end

          defp update_config(conn, config) do
            pubsub = config[:pubsub] || config.context[:pubsub] || conn.private[:phoenix_endpoint]

            if pubsub do
              put_in(config, [:context, :pubsub], pubsub)
            else
              config
            end
          end

          def subscribe(conn, topic, %{context: %{pubsub: pubsub}} = config) do
            pubsub.subscribe(topic)

            conn
            |> put_resp_header("content-type", "text/event-stream")
            |> send_chunked(200)
            |> subscribe_loop(topic, config)
          end

          def subscribe_loop(conn, topic, config) do
            receive do
              %{event: "subscription:data", payload: %{result: result}} ->
                case chunk(conn, "#{encode_json!(result, config)}\n\n") do
                  {:ok, conn} ->
                    subscribe_loop(conn, topic, config)

                  {:error, :closed} ->
                    Absinthe.Subscription.unsubscribe(config.context.pubsub, topic)
                    conn
                end

              :close ->
                Absinthe.Subscription.unsubscribe(config.context.pubsub, topic)
                conn
            after
              30_000 ->
                case chunk(conn, ":ping\n\n") do
                  {:ok, conn} ->
                    subscribe_loop(conn, topic, config)

                  {:error, :closed} ->
                    Absinthe.Subscription.unsubscribe(config.context.pubsub, topic)
                    conn
                end
            end
          end

          @doc """
          Sets the options for a given GraphQL document execution.

          ## Examples

              iex> Absinthe.Plug.put_options(conn, context: %{current_user: user})
              %Plug.Conn{}
          """
          @spec put_options(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
          def put_options(%Plug.Conn{private: %{absinthe: absinthe}} = conn, opts) do
            opts = Map.merge(absinthe, Enum.into(opts, %{}))
            Plug.Conn.put_private(conn, :absinthe, opts)
          end

          def put_options(conn, opts) do
            Plug.Conn.put_private(conn, :absinthe, Enum.into(opts, %{}))
          end

          @doc false
          @spec execute(Plug.Conn.t(), map) :: {Plug.Conn.t(), any}
          def execute(conn, config) do
            conn_info = %{
              conn_private: (conn.private[:absinthe] || %{}) |> Map.put(:http_method, conn.method)
            }

            with {:ok, conn, request} <- Request.parse(conn, config),
                 {:ok, request} <- ensure_processable(request, config) do
              run_request(request, conn, conn_info, config)
            else
              result ->
                {conn, result}
            end
          end

          @doc false
          @spec ensure_processable(Request.t(), map) ::
                  {:ok, Request.t()} | {:input_error, String.t()}
          def ensure_processable(request, config) do
            with {:ok, request} <- ensure_documents(request, config) do
              ensure_document_provider(request)
            end
          end

          @spec ensure_documents(Request.t(), map) ::
                  {:ok, Request.t()} | {:input_error, String.t()}
          defp ensure_documents(%{queries: []}, config) do
            {:input_error, config.no_query_message}
          end

          defp ensure_documents(%{queries: queries} = request, config) do
            Enum.reduce_while(queries, {:ok, request}, fn query, _acc ->
              query_status =
                case query do
                  {:input_error, error_msg} -> {:input_error, error_msg}
                  query -> ensure_document(query, config)
                end

              case query_status do
                {:ok, _query} -> {:cont, {:ok, request}}
                {:input_error, error_msg} -> {:halt, {:input_error, error_msg}}
              end
            end)
          end

          @spec ensure_document(Request.t(), map) ::
                  {:ok, Request.t()} | {:input_error, String.t()}
          defp ensure_document(%{document: nil}, config) do
            {:input_error, config.no_query_message}
          end

          defp ensure_document(%{document: _} = query, _) do
            {:ok, query}
          end

          @spec ensure_document_provider(Request.t()) ::
                  {:ok, Request.t()} | {:input_error, String.t()}
          defp ensure_document_provider(%{queries: queries} = request) do
            if Enum.all?(queries, &Map.has_key?(&1, :document_provider)) do
              {:ok, request}
            else
              {:input_error, "No document provider found to handle this request"}
            end
          end

          @doc false
          def run_request(%{batch: true, queries: queries} = request, conn, conn_info, config) do
            Request.log(request, config.log_level)
            {conn, results} = Absinthe.Plug.Batch.Runner.run(queries, conn, conn_info, config)

            results =
              results
              |> Enum.zip(request.extra_keys)
              |> Enum.map(fn {result, extra_keys} ->
                Map.merge(extra_keys, %{
                  payload: result
                })
              end)

            {conn, {:ok, results}}
          end

          def run_request(%{batch: false, queries: [query]} = request, conn, conn_info, config) do
            Request.log(request, config.log_level)
            run_query(query, conn, conn_info, config)
          end

          defp run_query(query, conn, conn_info, config) do
            %{document: document, pipeline: pipeline} =
              Request.Query.add_pipeline(query, conn_info, config)

            case Absinthe.Pipeline.run(document, pipeline) do
              {:ok, %{result: result} = bp, _} ->
                conn = apply_before_send(conn, [bp], config)
                {conn, {:ok, result}}

              val ->
                {conn, val}
            end
          end

          #
          # PIPELINE
          #

          @doc """
          The default pipeline used to process GraphQL documents.

          This consists of Absinthe's default pipeline (as returned by `Absinthe.Pipeline.for_document/1`),
          with the `Absinthe.Plug.Validation.HTTPMethod` phase inserted to ensure that the correct
          HTTP verb is being used for the GraphQL operation type.
          """
          @spec default_pipeline(map, Keyword.t()) :: Absinthe.Pipeline.t()
          def default_pipeline(config, pipeline_opts) do
            config.schema_mod
            |> Absinthe.Pipeline.for_document(pipeline_opts)
            |> Absinthe.Pipeline.insert_after(
              Absinthe.Phase.Document.CurrentOperation,
              [
                {Absinthe.Plug.Validation.HTTPMethod, method: config.conn_private.http_method}
              ]
            )
          end

          #
          # DOCUMENT PROVIDERS
          #

          @doc """
          The default list of document providers that are enabled.

          This consists of a single document provider, `Absinthe.Plug.DocumentProvider.Default`, which
          supports ad hoc GraphQL documents provided directly within the request.

          For more information about document providers, see `Absinthe.Plug.DocumentProvider`.
          """
          @spec default_document_providers(map) :: [Absinthe.Plug.DocumentProvider.t()]
          def default_document_providers(_) do
            [Absinthe.Plug.DocumentProvider.Default]
          end

          #
          # SERIALIZATION
          #

          @doc false
          @spec encode(Plug.Conn.t(), 200 | 400 | 405 | 500, String.t(), map) ::
                  Plug.Conn.t() | no_return
          def encode(conn, status, body, %{
                serializer: %{module: mod, opts: opts},
                content_type: content_type
              }) do
            conn
            |> put_resp_content_type(content_type)
            |> send_resp(status, mod.encode!(body, opts))
          end

          @doc false
          def encode_json!(value, %{json_codec: json_codec}) do
            json_codec.module.encode!(value, json_codec.opts)
          end

          @doc false
          def error_result(message), do: %{"errors" => [%{"message" => message}]}
        end
      )
    end
  end
end
