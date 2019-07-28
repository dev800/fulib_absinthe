defmodule FulibAbsinthe.SchemaHelpers do
  @moduledoc """
  iex>
    use FulibAbsinthe.SchemaHelpers,
      resolver_helper: Worth.ResolverHelper,
      target_logic: Worth.TargetLogic
  """

  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :resolver_helper, accumulate: false)
      Module.put_attribute(__MODULE__, :resolver_helper, opts[:resolver_helper])

      Module.register_attribute(__MODULE__, :target_logic, accumulate: false)
      Module.put_attribute(__MODULE__, :target_logic, opts[:target_logic])

      Module.eval_quoted(
        __MODULE__,
        quote do
          import Absinthe.Resolution.Helpers
          require Ecto.Query

          def batch_by_field([model_module, right | opts], values) do
            values = values |> List.flatten() |> Enum.uniq()
            preload = Fulib.get(opts, :preload, [])
            query_handle_fn = opts[:query_handle_fn] || fn query, _opts -> query end
            opts = opts |> Keyword.drop([:preload, :query_handle_fn])

            model_module.where([{right, values}])
            |> model_module.preload(preload)
            |> query_handle_fn.(opts)
            |> model_module.repo.all
            |> Map.new(&{Fulib.get(&1, right), &1})
          end

          def preload(left, model_module, opts \\ [])

          def preload(left, {model_module, right}, opts) do
            preload(left, {__MODULE__, :batch_by_field, [model_module, right]}, opts)
          end

          def preload(left, {helper_module, fun, args}, opts) when is_list(args) do
            fn parent, params, resolution ->
              current_user = resolution |> @resolver_helper.get_current_user()

              results_handle_fn =
                opts[:results_handle_fn] ||
                  fn results, _parent, _params, _resolution -> results end

              args = args ++ Fulib.reverse_merge(opts, params: params, current_user: current_user)

              case left do
                {:array, left} ->
                  batch({helper_module, fun, args}, Fulib.get(parent, left), fn batch_results ->
                    batch_entries =
                      Fulib.get(parent, left, [])
                      |> Enum.map(fn key -> batch_results |> Fulib.get(key) end)
                      |> Fulib.compact()

                    {:ok, results_handle_fn.(batch_entries, parent, params, resolution)}
                  end)

                left ->
                  batch({helper_module, fun, args}, Fulib.get(parent, left), fn batch_results ->
                    {:ok,
                     results_handle_fn.(
                       batch_results |> Map.get(Fulib.get(parent, left)),
                       parent,
                       params,
                       resolution
                     )}
                  end)
              end
            end
          end

          def preload(left, model_module, opts),
            do: preload(left, {model_module, model_module.repo_primary_key()}, opts)

          def results_handle_fn(opts) do
            fn entries, parent, params, resolution ->
              if opts[:results_handle_fn] do
                opts[:results_handle_fn].(entries, parent, params, resolution)
              else
                entries
              end
            end
          end

          @doc """
          ## opts

          ```
          query_handle_fn: fn query, opts ->
            # opts
            #   * :params
            #   * :left
            #   * :right
          end
          ```
          """
          def batch_counter([model_module, right | opts], values) do
            values = values |> List.flatten() |> Enum.uniq()
            query_handle_fn = opts[:query_handle_fn] || fn query, _opts -> query end
            opts = opts |> Keyword.drop([:preload, :query_handle_fn])
            repo_primary_key = model_module.repo_primary_key()

            Ecto.Query.from(r1 in model_module,
              group_by: field(r1, ^right),
              select: %{group: field(r1, ^right), count: count(field(r1, ^repo_primary_key))}
            )
            |> query_handle_fn.(opts)
            |> model_module.repo.all
            |> Enum.map(fn record ->
              {record.group, record.count}
            end)
            |> Map.new()
          end

          def counter_preload(left, model_module, opts \\ [])

          def counter_preload(left, {model_module, right}, opts) do
            counter_preload(left, {__MODULE__, :batch_counter, [model_module, right]}, opts)
          end

          def counter_preload(left, {helper_module, fun, args}, opts) when is_list(args) do
            fn parent, params, resolution ->
              current_user = resolution |> @resolver_helper.get_current_user()

              args = args ++ Fulib.reverse_merge(opts, params: params, current_user: current_user)

              case left do
                {:array, left} ->
                  batch(
                    {helper_module, fun, args ++ [left: left]},
                    Fulib.get(parent, left),
                    fn batch_results ->
                      batch_entries =
                        Fulib.get(parent, left, [])
                        |> Enum.map(fn key -> batch_results |> Fulib.get(key) end)
                        |> Fulib.compact()

                      {:ok, batch_entries}
                    end
                  )

                left ->
                  batch(
                    {helper_module, fun, args ++ [left: left]},
                    Fulib.get(parent, left),
                    fn batch_results ->
                      {:ok, batch_results |> Map.get(Fulib.get(parent, left)) |> Fulib.to_i()}
                    end
                  )
              end
            end
          end

          @doc """
          ## opts

          ```
          query_handle_fn: fn query, opts ->
            # opts
            #   * :params
            #   * :left
            #   * :right
          end
          ```
          """
          def batch_by_groups([model_module, right | opts], values) do
            values = values |> List.flatten() |> Enum.uniq()
            params = opts[:params] || %{}
            left = opts[:left]
            preload = Fulib.get(opts, :preload, [])
            query_handle_fn = opts[:query_handle_fn] || fn query, _opts -> query end
            subquery_handle_fn = opts[:subquery_handle_fn]
            opts = opts |> Keyword.drop([:preload, :query_handle_fn, :subquery_handle_fn])
            limit = params |> Fulib.get(:limit, 10) |> Fulib.to_i()
            page_number = params |> Fulib.get(:page_number, 1) |> Fulib.to_i()
            offset = limit * (page_number - 1)
            pageable = params |> Fulib.get(:pageable, true)
            page_style = :count

            # TODO: 需要增加order by的排序支持
            subquery =
              Ecto.Query.from(t in model_module, where: field(t, ^right) in ^values)
              |> query_handle_fn.(opts)
              |> Fulib.if_call(true, fn query ->
                if subquery_handle_fn do
                  query |> subquery_handle_fn.(opts)
                else
                  Ecto.Query.from(t in query,
                    select: %{
                      left: field(t, ^left),
                      right: field(t, ^right),
                      total_entries:
                        fragment(
                          "COUNT(?) OVER(PARTITION BY ?)",
                          field(t, ^left),
                          field(t, ^right)
                        ),
                      rank:
                        fragment(
                          "RANK() OVER(PARTITION BY ? ORDER BY ? DESC)",
                          field(t, ^right),
                          field(t, ^left)
                        )
                    }
                  )
                end
              end)

            if pageable do
              Ecto.Query.from(r1 in model_module,
                join: r2 in subquery(subquery),
                on: field(r1, ^left) == r2.left,
                where: r2.rank <= ^(offset + limit),
                where: r2.rank > ^offset,
                select: %{record: r1, rank: r2.rank, total_entries: r2.total_entries}
              )
            else
              Ecto.Query.from(r1 in model_module,
                join: r2 in subquery(subquery),
                on: field(r1, ^left) == r2.left,
                select: %{record: r1, rank: r2.rank, total_entries: r2.total_entries}
              )
            end
            |> model_module.preload(preload)
            |> query_handle_fn.(opts)
            |> model_module.repo.all
            |> Enum.group_by(fn %{record: record} ->
              record |> Fulib.get(right)
            end)
            |> Enum.map(fn {right_id, records} ->
              total_entries =
                records
                |> Fulib.List.first()
                |> Fulib.get(:total_entries)
                |> Fulib.to_i()

              entries = records |> Enum.map(fn %{record: record} -> record end)

              paginater =
                if pageable do
                  total_pages = Fulib.Paginater.Util.get_total_pages(total_entries, limit: limit)

                  %Fulib.Paginater.CountResult{
                    is_first: page_number <= 1,
                    is_last: page_number >= total_pages,
                    entries: entries,
                    limit: limit,
                    offset: offset,
                    per_page: limit,
                    page_number: page_number,
                    total_entries: total_entries,
                    total_pages: total_pages
                  }
                else
                  %Fulib.Paginater.AllResult{
                    entries: entries
                  }
                end

              {right_id, paginater}
            end)
            |> Map.new()
          end

          def groups_preload(left, model_module, opts \\ [])

          def groups_preload(left, {model_module, right}, opts) do
            groups_preload(left, {__MODULE__, :batch_by_groups, [model_module, right]}, opts)
          end

          def groups_preload(left, {helper_module, fun, args}, opts) when is_list(args) do
            fn parent, params, resolution ->
              current_user = resolution |> @resolver_helper.get_current_user()

              args = args ++ Fulib.reverse_merge(opts, params: params, current_user: current_user)

              case left do
                {:array, left} ->
                  batch(
                    {helper_module, fun, args ++ [left: left]},
                    Fulib.get(parent, left),
                    fn batch_results ->
                      batch_entries =
                        Fulib.get(parent, left, [])
                        |> Enum.map(fn key -> batch_results |> Fulib.get(key) end)
                        |> Fulib.compact()

                      {:ok, batch_entries}
                    end
                  )

                left ->
                  batch(
                    {helper_module, fun, args ++ [left: left]},
                    Fulib.get(parent, left),
                    fn batch_results ->
                      {:ok, batch_results |> Map.get(Fulib.get(parent, left))}
                    end
                  )
              end
            end
          end

          def polymorphic_preload(left, type_key, opts \\ []) do
            fn parent, params, _resolution ->
              opts = Fulib.reverse_merge(opts, params: params)

              polymorphic_module =
                parent
                |> Fulib.get(type_key)
                |> @target_logic.get_polymorphic_module()

              if polymorphic_module do
                primary_key = polymorphic_module.repo_primary_key

                batch(
                  {__MODULE__, :batch_by_field, [polymorphic_module, primary_key, opts]},
                  Fulib.get(parent, left),
                  fn batch_results ->
                    {:ok, batch_results |> Map.get(Fulib.get(parent, left))}
                  end
                )
              end
            end
          end

          def format_date(key, format_key \\ :format) do
            fn father, params, _resolution ->
              datetime = father |> Fulib.get(key)
              format = params |> Fulib.get(format_key, "utc_strftime", "utc_strftime")
              {:ok, FulibAbsinthe.DateHelper.format!(datetime, format)}
            end
          end

          def serialize_tuple_to_response({status, message}) do
            status = if :ok == status, do: :ok, else: :error
            {status, %{status: status, message: message}}
          end

          def serialize_option_to_map({name, key}) do
            serialize_option_to_map([name, key])
          end

          def serialize_option_to_map([name, key]) do
            %{name: Fulib.to_s(name), key: Fulib.to_s(key)}
          end

          def plus_one(parent, _, _) do
            {:ok, (parent |> Fulib.get(:position) |> Fulib.to_i()) + 1}
          end
        end
      )
    end
  end
end
