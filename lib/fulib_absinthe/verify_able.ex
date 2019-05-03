defmodule FulibAbsinthe.VerifyAble do
  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :helper, accumulate: false)
      Module.put_attribute(__MODULE__, :helper, opts[:helper])

      Module.eval_quoted(
        __MODULE__,
        quote do
          import Ecto.Changeset

          def try(%Ecto.Changeset{valid?: false} = changeset, _ok_fn), do: changeset
          def try(changeset, ok_fn), do: ok_fn.(changeset)

          def validate_fields(changeset, rules \\ %{}, rule_keys \\ %{}) do
            case changeset do
              %Ecto.Changeset{valid?: false} ->
                changeset

              changeset ->
                changeset |> Fulib.Validate.validate_changeset(rules, rule_keys)
            end
          end

          @doc """
          必须要`field_key`这个字段
          """
          def required(changeset, entry, field_key, opts \\ []) do
            ignore_nil = Fulib.get(opts, :ignore_nil, false)

            if Fulib.present?(entry) || (ignore_nil && is_nil(get_change(changeset, field_key))) do
              changeset
            else
              @helper.put_error(
                changeset,
                field_key,
                Fulib.get(opts, :message, "can't be blank"),
                opts |> Fulib.reverse_merge(validation: :required)
              )
            end
          end

          @doc """
          不能被占用

          ## opts

          * `:query_fn`
          * `:action` 操作, 可选值为：:insert(默认), :update
          * `:primary_key` 主键，默认为: :id, 当action == :update时，需要排除当前记录
          """
          def unique(changeset, model_module, field_key, opts \\ []) do
            query_fn = opts |> Fulib.get(:query_fn, fn query -> query end)
            action = opts |> Fulib.get(:action, :insert)
            primary_key = opts |> Fulib.get(:primary_key, :id)
            query_key = opts |> Fulib.get(:query_key, field_key)

            changeset
            |> Fulib.Form.get_param(field_key)
            |> case do
              nil ->
                changeset

              field_value ->
                basic_conditions = Keyword.new([{query_key, field_value}])

                case action do
                  :insert ->
                    model_module.get_by(basic_conditions) |> query_fn.()

                  :update ->
                    basic_conditions
                    |> model_module.where()
                    |> query_fn.()
                    |> model_module.queryable_find(primary_key)

                  _ ->
                    raise "opts[:action] must in [:insert, :update]"
                end
                |> case do
                  nil ->
                    changeset

                  _ ->
                    @helper.put_error(
                      changeset,
                      field_key,
                      Fulib.get(opts, :message, "has already been taken"),
                      validation: :unique_constraint
                    )
                end
            end
          end

          @doc """
          必须存在

          ## opts

          * `:query_fn`
          """
          def exist(changeset, model_module, field_key, entry_key, opts \\ []) do
            query_fn = opts |> Fulib.get(:query_fn, fn query -> query end)
            query_key = opts |> Fulib.get(:query_key, field_key)

            changeset
            |> Fulib.Form.get_param(field_key)
            |> case do
              nil ->
                changeset

              field_value ->
                basic_conditions = Keyword.new([{query_key, field_value}])

                basic_conditions
                |> model_module.where()
                |> query_fn.()
                |> model_module.queryable_get_by([])
                |> case do
                  nil ->
                    @helper.put_error(
                      changeset,
                      field_key,
                      Fulib.get(opts, :message, "not found"),
                      validation: :not_found
                    )

                  entry ->
                    changeset |> Fulib.Form.put_entry(entry_key, entry)
                end
            end
          end

          @doc """
          `field_key` 对应的 `entry`这个字段必须存在
          """
          def must_exist(changeset, entry, field_key, opts \\ []) do
            ignore_nil = Fulib.get(opts, :ignore_nil, false)

            if entry || (ignore_nil && is_nil(get_change(changeset, field_key))) do
              changeset
            else
              @helper.put_error(
                changeset,
                field_key,
                Fulib.get(opts, :message, "not found"),
                opts |> Fulib.reverse_merge(validation: :not_found)
              )
            end
          end

          def cannot_equal(changeset, key_left, key_right, opts \\ []) do
            val_left = get_change(changeset, key_left)
            val_right = get_change(changeset, key_right)

            cond do
              is_nil(val_left) or is_nil(val_right) ->
                changeset

              val_left == val_right ->
                @helper.put_error(
                  changeset,
                  key_left,
                  Fulib.get(opts, :message, "can't be equal to #{key_right}(%{value})"),
                  opts |> Fulib.reverse_merge(validation: :cannot_equal, value: val_left)
                )

              true ->
                changeset
            end
          end
        end
      )
    end
  end
end
