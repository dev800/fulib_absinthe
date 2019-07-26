defmodule FulibAbsinthe.ResolverHelper do
  @moduledoc """
  iex>
    use FulibAbsinthe.ResolverHelper,
      default_error: "default error",
      translator: Fulib.Translator
  """
  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :default_error, accumulate: false)
      Module.put_attribute(__MODULE__, :default_error, opts[:default_error] || "default error")

      Module.register_attribute(__MODULE__, :translator, accumulate: false)
      Module.put_attribute(__MODULE__, :translator, opts[:translator] || Fulib.Translator)

      Module.eval_quoted(
        __MODULE__,
        quote do
          defdelegate paginate_render(former, entry_key), to: __MODULE__, as: :pick_render

          def pick_render(%Fulib.Form{valid?: false} = former, _entry_key) do
            render(former)
          end

          def pick_render(%Fulib.Form{valid?: true, entries: entries}, entry_key) do
            {:ok, entries |> Fulib.get(entry_key)} |> render()
          end

          def take_render(%Fulib.Form{valid?: false} = former, _entry_key) do
            render(former)
          end

          def take_render(%Fulib.Form{valid?: true, entries: entries}, entry_keys) do
            {:ok, entries |> Fulib.take(entry_keys |> Fulib.to_array())} |> render()
          end

          def enum_types_resolve(type_module) do
            fn _parent, _params, _resolution ->
              {:ok,
               type_module.select_options()
               |> Enum.map(fn [name, key | _] ->
                 %{key: key, name: name}
               end)}
            end
          end

          @doc """
          渲染resolver结果，进行标准化

              iex> Worth.ResolverHelper.render(%Fulib.Form{
                     value?: false,
                     errors: [input_value: {"can't be blank", [validation: :required]}]
                   })

              iex> Worth.ResolverHelper.render(
                     {:error, %{errors: [input_value: {"can't be blank", [validation: :required]}]}}
                   )
          """
          def render(%Fulib.Form{valid?: false} = former, _success_fn) do
            former = former.module.translate(former)

            render(
              {:error,
               %{
                 errors: former.errors,
                 human: former.human,
                 human_errors: former.human_errors,
                 human_fields: former.human_fields
               }}
            )
          end

          def render({:error, data}, _success_fn) do
            data = data |> Fulib.reverse_merge(%{status: :error})
            human_fields = data |> Fulib.get(:human_fields, %{})

            errors =
              (Fulib.get(data, :human_errors) ||
                 [
                   {:base,
                    {Fulib.get(data, :message, @default_error),
                     Fulib.Translator.dgettext("errors", @default_error, []),
                     validation: Fulib.get(data, :logic, :error)}}
                 ])
              |> Enum.map(fn {key, {msgid, human_message, error_opts}} ->
                %{
                  key: key,
                  field: human_fields |> Fulib.get(key, key),
                  msgid: msgid,
                  message: human_message,
                  logic: Fulib.get(error_opts, :validation, :invalid)
                }
              end)
              |> Fulib.compact()

            error = errors |> Fulib.List.first()
            logic = error |> Fulib.get(:logic, "default")
            message_key = error[:key] || :base

            message_value =
              error[:message] || Fulib.Translator.dgettext("errors", @default_error, [])

            message =
              if message_key == :base || Fulib.blank?(message_value) do
                message_value
              else
                "#{error[:field]}#{
                  String.replace(@translator.dgettext("default", "words_gap"), "words_gap", "")
                }#{message_value}"
              end

            {:ok,
             data
             |> Fulib.put(:errors, errors)
             |> Fulib.reverse_merge(%{message: message, logic: logic})}
          end

          def render(%Fulib.Form{valid?: true, entries: entries}, success_fn) do
            render(entries, success_fn)
          end

          def render({:ok, entries}, success_fn) do
            render(entries, success_fn)
          end

          def render(entries, success_fn) do
            (success_fn.(entries) || entries) |> render_ok()
          end

          def render(former) do
            render(former, fn entries -> entries || %{} end)
          end

          def render_ok(data \\ %{}) do
            data =
              data
              |> Fulib.atom_keys_deep!()
              |> Fulib.reverse_merge(%{
                status: :ok,
                logic: "default",
                errors: [],
                message: "Succuss"
              })

            {:ok, data}
          end

          def try({:error, _} = result, _try_fn) do
            result
          end

          def try({:ok, %{status: "error"}} = result, _try_fn) do
            result
          end

          def try(result, try_fn) do
            try_fn.(result) || result
          end

          def get_current_user(%Absinthe.Resolution{} = resolution) do
            resolution.context |> Fulib.get(:current_user)
          end

          def get_current_user(_), do: nil

          def authorize(resolution) do
            render_ok() |> authorize(resolution)
          end

          def authorize(result, resolution) do
            try(result, fn result ->
              current_user = get_current_user(resolution)

              cond do
                is_nil(current_user) ->
                  {:error,
                   %{
                     errors: [
                       {:base, {"please login", validation: "require_login"}}
                     ],
                     human_errors: [
                       {:base,
                        {"please login", Fulib.Translator.dgettext("errors", "please login", []),
                         validation: "require_login"}}
                     ],
                     status: "error",
                     logic: "require_login"
                   }}

                true ->
                  result
              end
            end)
            |> render()
          end

          def get_action(%Absinthe.Resolution{context: %Plug.Conn{} = conn}) do
            conn
            |> Plug.Conn.get_req_header("request-action")
            |> Fulib.List.first()
            |> Fulib.to_atom()
            |> get_action()
          end

          def get_action(action) when action in [:insert, :update, :delete, :replace, :verify],
            do: action

          def get_action(_), do: :insert
        end
      )
    end
  end
end
