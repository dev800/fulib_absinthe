defmodule FulibAbsinthe.ConnHelper do
  defmacro __using__(opts \\ []) do
    quote do
      _opts = unquote(opts)

      Module.eval_quoted(
        __MODULE__,
        quote do
          def redirect!(conn, url) do
            html = Plug.HTML.html_escape(url)
            body = "<html><body>You are being <a href=\"#{html}\">redirected</a>.</body></html>"

            conn
            |> Plug.Conn.put_resp_header("location", url)
            |> Plug.Conn.send_resp(conn.status || 302, body)
            |> Plug.Conn.halt
          end

          def get_remote_ip(%Absinthe.Resolution{context: context}) do
            get_remote_ip(context)
          end

          def get_remote_ip(%Plug.Conn{} = conn) do
            x_forwarded_for =
              conn
              |> Plug.Conn.get_req_header("x-forwarded-for")
              |> Fulib.List.first()
              |> Fulib.to_s()
              |> String.split([",", " "], trim: true)
              |> Fulib.List.first()

            cond do
              x_forwarded_for && Fulib.Const.ip_match?(x_forwarded_for) ->
                x_forwarded_for

              true ->
                (conn.remote_ip || {}) |> Tuple.to_list() |> Enum.join(".")
            end
          end

          def get_remote_ip(_), do: ""

          def get_user_agent(%Absinthe.Resolution{context: context}) do
            get_user_agent(context)
          end

          def get_user_agent(%Plug.Conn{} = conn) do
            conn
            |> Plug.Conn.get_req_header("user-agent")
            |> Fulib.List.first()
            |> Fulib.to_s()
          end

          def get_user_agent(_), do: ""
        end
      )
    end
  end
end
