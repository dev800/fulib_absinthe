defmodule FulibAbsinthe.ChangesetHelper do
  defmacro __using__(opts \\ []) do
    quote do
      _opts = unquote(opts)

      Module.eval_quoted(
        __MODULE__,
        quote do
          @doc """
          iex> put_error(changeset, :name, msgid, validation: :required)
          iex> put_error(changeset, {:error, reason}, _message, keys)
          iex> put_error(changeset, {:error, %{__struct__: _} = error}, msgid, keys)
          iex> put_error(changeset, {:error, key, reason, msgid}, message, keys)
          iex> put_error(changeset, {:error, key, reason, {msgid, _bindings}}, _message, keys)
          iex> put_error(changeset, {:error, key, reason}, _message, keys)
          iex> put_error(changeset, key, msgid, keys)
          """
          def put_error(changeset, key, message \\ "Process fail", keys \\ [])

          def put_error(
                changeset,
                %Ecto.InvalidChangesetError{changeset: %Ecto.Changeset{errors: errors}},
                _default_message,
                _opts
              ) do
            Enum.reduce(errors, changeset, fn {key, {message, keys}}, changeset ->
              put_error(changeset, key, message, keys)
            end)
          end

          def put_error(
                changeset,
                %Ecto.NoPrimaryKeyValueError{message: message, struct: _},
                _default_message,
                _opts
              ) do
            put_error(changeset, :base, message, validation: :invalid)
          end

          def put_error(
                changeset,
                %Ecto.ConstraintError{constraint: constraint, type: type},
                _default_message,
                _opts
              ) do
            put_error(changeset, :base, "constraint error: #{constraint}", validation: type)
          end

          def put_error(changeset, {:error, key, reason}, _message, keys) do
            put_error(
              changeset,
              key,
              "#{reason}",
              keys |> Fulib.reverse_merge(validation: reason)
            )
          end

          def put_error(changeset, {:error, key, reason, {msgid, _bindings}}, _message, keys) do
            put_error(changeset, key, msgid, keys |> Fulib.reverse_merge(validation: reason))
          end

          def put_error(changeset, {:error, key, reason, msgid}, message, keys) do
            put_error(changeset, {:error, key, reason, {msgid, []}}, message, keys)
          end

          def put_error(changeset, {:error, %{__struct__: _} = error}, msgid, keys) do
            put_error(changeset, error, msgid, keys)
          end

          def put_error(changeset, {:error, reason}, _message, keys) do
            put_error(
              changeset,
              :base,
              "#{reason}",
              keys |> Fulib.reverse_merge(validation: reason)
            )
          end

          def put_error(changeset, key, msgid, keys) do
            Ecto.Changeset.add_error(changeset, key, msgid, keys)
          end
        end
      )
    end
  end
end
