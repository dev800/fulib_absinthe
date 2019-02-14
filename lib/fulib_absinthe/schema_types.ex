defmodule FulibAbsinthe.SchemaTypes do
  @moduledoc """
  GraphQL Schema Type
  扩展类型
  """

  defmacro __using__(opts) do
    quote do
      opts = unquote(opts)

      Module.register_attribute(__MODULE__, :helpers_module, accumulate: false)
      Module.put_attribute(__MODULE__, :helpers_module, opts[:helpers_module])

      import FulibAbsinthe.SchemaTypes
      require FulibAbsinthe.SchemaTypes
    end
  end

  use Absinthe.Schema.Notation

  enum :switcher do
    value(:open)
    value(:close)
  end

  scalar :atom, description: "atom" do
    parse(&{:ok, Fulib.to_atom(Fulib.get(&1, :value))})
    serialize(&Fulib.to_s(&1))
  end

  scalar :csl, description: "Comma-Separated List" do
    parse(&{:ok, String.split(Fulib.get(&1, :value), ",", trim: true)})
    serialize(&Enum.join(&1, ","))
  end

  scalar :string_date, description: "年-月-日" do
    parse(&Timex.parse(Fulib.get(&1, :value), "{YYYY}-{M}-{D}"))
    serialize(&Timex.format!(&1, "{YYYY}-{M}-{D}"))
  end

  defmacro field_response(response_type, do: response_body) do
    quote do
      field unquote(:"#{response_type}"), unquote(:"#{response_type}_response") do
        unquote(response_body)
      end
    end
  end

  defmacro field_enumable(field_key, opts \\ []) do
    quote do
      field unquote(:"#{field_key}_human"), :string, unquote(opts) do
        resolve(fn parent, _params, _resolution ->
          if parent do
            field_key = unquote(field_key)
            value = parent |> Fulib.get(field_key)
            type_module = parent.__struct__.__changeset__ |> Fulib.get(field_key)

            if is_nil(value) do
              {:ok, nil}
            else
              {:ok, type_module.get_human(value)}
            end
          else
            {:ok, nil}
          end
        end)
      end

      field unquote(:"#{field_key}"), :string, unquote(opts) do
        resolve(fn parent, _params, _resolution ->
          if parent do
            {:ok, parent |> Fulib.get(unquote(field_key))}
          else
            {:ok, nil}
          end
        end)
      end
    end
  end

  defmacro field_datetime(field_key, opts \\ []) do
    quote do
      field unquote(field_key), :string do
        arg(
          :format,
          :string,
          default_value: unquote(Fulib.get(opts, :default_format, "utc_strftime")),
          description: """
          时间格式:
          * utc_strftime eg. 2017-03-10T01:38:12Z,
          * human 返回可读化日期，
          * time 返回 24 小时时间，
          * date 只返回日期
          * datetime 返回24小时时间+日期，
          * 其它自定义如 {YYYY}-{M}-{D}。
          """
        )

        resolve(@helpers_module.format_date(unquote(field_key)))
      end
    end
  end

  object :response do
    field(:status, :string, description: "状态")
    field(:message, :string, description: "提示原因")
    field(:errors, list_of(:error), description: "错误域")
  end

  object :error do
    field(:key, :string, description: "字段Key")
    field(:field, :string, description: "字段名称")
    field(:logic, :string, description: "业务逻辑状态")
    field(:message, :string, description: "提示消息")
  end

  @desc "权限"
  object :ability do
    field(:key, :string, description: "权限")
    field(:reason, :string, description: "原因")

    field(:value, :string,
      description: """
      能力值：

      * yes 可以
      * no 不可以
      """
    ) do
      resolve(fn parent, _params, _resolution ->
        value =
          parent
          |> Fulib.get(:value)
          |> case do
            true -> "yes"
            false -> "no"
            _ -> nil
          end

        {:ok, value}
      end)
    end
  end

  @desc "选项"
  object :option do
    field(:name, :string, description: "显示内容")
    field(:key, :string, description: "Key")
  end

  defmacro object_response_empty(response_type) do
    quote do
      object_response(unquote(:"#{response_type}")) do
      end
    end
  end

  defmacro object_response(response_type) do
    quote do
      object_response(unquote(:"#{response_type}")) do
        field(unquote(:"#{response_type}"), unquote(:"#{response_type}"))
      end
    end
  end

  defmacro object_response(response_type, do: response_body) do
    quote do
      object unquote(:"#{response_type}_response") do
        field(:status, :string, description: "ok")
        field(:message, :string, description: "操作成功")
        field(:logic, :string, description: "业务逻辑状态")
        field(:errors, list_of(:error), description: "错误域")

        unquote(response_body)
      end
    end
  end

  defmacro object_paginater(entry_type, opts \\ []) do
    quote do
      object unquote(Fulib.to_atom(["paginater", "_", Fulib.to_s(entry_type)])) do
        field(:style, :string, description: "分页形式")
        field(:limit, :integer, description: "返回条数")
        field(:max_page, :integer, description: "最大页数")
        field(:page_number, :integer, description: "页码")
        field(:per_page, :integer, description: "每页条数")
        field(:total_entries, :integer, description: "总条数")
        field(:total_pages, :integer, description: "总页数")
        field(:entries, list_of(unquote(entry_type)), description: "数据对象")
        field(:status, :string, description: "状态")
        field(:message, :string, description: "操作成功")
        field(:logic, :string, description: "业务逻辑状态")
        field(:errors, list_of(:error), description: "错误域")

        unquote(opts[:do])
      end
    end
  end

  defmacro field_paginater(field_name, {:list_of, _, [field_type]}, opts \\ []) do
    quote do
      field unquote(field_name),
            unquote(Fulib.to_atom(["paginater", "_", Fulib.to_s(field_type)])) do
        arg(:offset, :integer, description: "偏移量")
        arg(:limit, :integer, description: "每页条数")
        arg(:page_number, :integer, description: "当前页数")
        arg(:page_style, :atom, description: "分页类型")

        unquote(opts[:do])
      end
    end
  end
end
