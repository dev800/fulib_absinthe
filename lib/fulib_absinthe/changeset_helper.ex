defmodule FulibAbsinthe.ChangesetHelper do
  defmacro __using__(opts \\ []) do
    quote do
      _opts = unquote(opts)

      Module.eval_quoted(
        __MODULE__,
        quote do
          import ShorterMaps
          require Logger

          def try(changeset, start_fn) do
            __MODULE__.try(changeset, start_fn, fn changeset, data ->
              changeset |> Fulib.Form.put_entries(data)
            end)
          end

          def try(changeset, start_fn, ok_fn) do
            try do
              if changeset.valid? do
                changeset
                |> start_fn.()
                |> case do
                  {:ok, data} ->
                    ok_fn.(changeset, data)

                  error ->
                    put_error(changeset, error)
                end
              else
                changeset
              end
            catch
              :error, error ->
                Logger.error(__STACKTRACE__ |> inspect())
                put_error(changeset, error)
            end
          end

          @doc """
          iex> put_error(changeset, :name, msgid, validation: :required)
          iex> put_error(changeset, {:error, reason}, _message, opts)
          iex> put_error(changeset, {:error, %{__struct__: _} = error}, msgid, opts)
          iex> put_error(changeset, {:error, field_key, reason, msgid}, message, opts)
          iex> put_error(changeset, {:error, field_key, reason, {msgid, _bindings}}, _message, opts)
          iex> put_error(changeset, {:error, field_key, reason}, _message, opts)
          iex> put_error(changeset, field_key, msgid, opts)
          """
          def put_error(changeset, error, message \\ "Process fail", opts \\ [])

          def put_error(changeset, [], _message, _opts) do
            changeset
          end

          def put_error(changeset, [error | errors], message, opts) do
            changeset
            |> put_error(error, message, opts)
            |> put_error(errors, message, opts)
          end

          # put_error(changeset, %Ecto.InvalidChangesetError{}, default_message, opts)
          def put_error(
                changeset,
                %Ecto.InvalidChangesetError{changeset: %Ecto.Changeset{errors: errors}},
                _default_message,
                _opts
              ) do
            Enum.reduce(errors, changeset, fn {field_key, {message, opts}}, changeset ->
              put_error(changeset, field_key, message, opts)
            end)
          end

          # put_error(changeset, %Ecto.NoPrimaryKeyValueError{}, default_message, opts)
          def put_error(
                changeset,
                %Ecto.NoPrimaryKeyValueError{message: message, struct: _},
                _default_message,
                _opts
              ) do
            put_error(changeset, :base, message, validation: :invalid)
          end

          # put_error(changeset, %Ecto.ConstraintError{}, default_message, opts)
          def put_error(
                changeset,
                %Ecto.ConstraintError{constraint: constraint, type: type},
                _default_message,
                _opts
              ) do
            put_error(changeset, :base, "constraint error: #{constraint}", validation: type)
          end

          def put_error(
                changeset,
                {:error, reason, %{msgid: msgid} = extends},
                default_message,
                opts
              ) do
            put_error(
              changeset,
              {
                :error,
                Fulib.get(extends, :field_key, :base),
                reason,
                {msgid, Fulib.get(extends, :bindings, [])}
              },
              default_message,
              opts
            )
          end

          # put_error(changeset, {:error, field_key, reason}, default_message, opts)
          def put_error(changeset, {:error, field_key, reason}, _message, opts) do
            put_error(
              changeset,
              field_key,
              reason |> Fulib.to_s(),
              opts |> Fulib.reverse_merge(validation: reason)
            )
          end

          # put_error(changeset, {:error, field_key, reason, {msgid, bindings}}, default_message, opts)
          def put_error(changeset, {:error, field_key, reason, {msgid, bindings}}, _message, opts) do
            put_error(
              changeset,
              field_key,
              msgid,
              opts |> Fulib.reverse_merge(bindings) |> Fulib.reverse_merge(validation: reason)
            )
          end

          def put_error(changeset, {:error, field_key, reason, msgid}, message, opts) do
            put_error(changeset, {:error, field_key, reason, {msgid, []}}, message, opts)
          end

          def put_error(changeset, {:error, %{__struct__: _} = error}, msgid, opts) do
            put_error(changeset, error, msgid, opts)
          end

          def put_error(changeset, {:error, reason}, _message, opts) do
            put_error(
              changeset,
              :base,
              reason |> Fulib.to_s(),
              opts |> Fulib.reverse_merge(validation: reason)
            )
          end

          def put_error(changeset, field_key, msgid, bindings) do
            Ecto.Changeset.add_error(changeset, field_key, msgid, bindings)
          end
        end
      )
    end
  end
end
