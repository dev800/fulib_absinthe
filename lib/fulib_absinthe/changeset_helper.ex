defmodule FulibAbsinthe.ChangesetHelper do
  defmacro __using__(opts \\ []) do
    quote do
      _opts = unquote(opts)

      Module.eval_quoted(
        __MODULE__,
        quote do
          import ShorterMaps

          @doc """
          iex> put_error(changeset, :name, msgid, validation: :required)
          iex> put_error(changeset, {:error, reason}, _message, opts)
          iex> put_error(changeset, {:error, %{__struct__: _} = error}, msgid, opts)
          iex> put_error(changeset, {:error, key, reason, msgid}, message, opts)
          iex> put_error(changeset, {:error, key, reason, {msgid, _bindings}}, _message, opts)
          iex> put_error(changeset, {:error, key, reason}, _message, opts)
          iex> put_error(changeset, key, msgid, opts)
          """
          def put_error(changeset, error, message \\ "Process fail", opts \\ [])

          # put_error(changeset, %Ecto.InvalidChangesetError{}, default_message, opts)
          def put_error(
                changeset,
                %Ecto.InvalidChangesetError{changeset: %Ecto.Changeset{errors: errors}},
                _default_message,
                _opts
              ) do
            Enum.reduce(errors, changeset, fn {key, {message, opts}}, changeset ->
              put_error(changeset, key, message, opts)
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

          def put_error(changeset, {:error, reason, %{msgid: msgid} = extends}, default_message, opts) do
            put_error(
              changeset,
              {
                :error,
                Fulib.get(extends, :key, :base),
                reason,
                {msgid, Fulib.get(extends, :bindings, [])}
              },
              default_message,
              opts
            )
          end

          # put_error(changeset, {:error, key, reason}, default_message, opts)
          def put_error(changeset, {:error, key, reason}, _message, opts) do
            put_error(
              changeset,
              key,
              reason |> Fulib.to_s(),
              opts |> Fulib.reverse_merge(validation: reason)
            )
          end

          # put_error(changeset, {:error, key, reason, {msgid, bindings}}, default_message, opts)
          def put_error(changeset, {:error, key, reason, {msgid, bindings}}, _message, opts) do
            put_error(
              changeset,
              key,
              msgid,
              opts |> Fulib.reverse_merge(bindings) |> Fulib.reverse_merge(validation: reason)
            )
          end

          def put_error(changeset, {:error, key, reason, msgid}, message, opts) do
            put_error(changeset, {:error, key, reason, {msgid, []}}, message, opts)
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

          def put_error(changeset, key, msgid, bindings) do
            Ecto.Changeset.add_error(changeset, key, msgid, bindings)
          end
        end
      )
    end
  end
end
