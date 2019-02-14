defmodule FulibAbsinthe.DateHelper do
  @default_format "utc_strftime"

  def format!(datetime, format \\ @default_format)

  def format!(datetime, format) do
    datetime
    |> format(format)
    |> case do
      {:ok, formated_datetime} ->
        formated_datetime

      _ ->
        datetime
    end
  end

  def format(datetime, format \\ @default_format)

  def format(datetime, "time") do
    Timex.format(datetime, "{h24}:{0m}")
  end

  def format(datetime, "date") do
    Timex.format(datetime, "{0M}-{0D}")
  end

  def format(datetime, "datetime") do
    Timex.format(datetime, "{0M}-{0D} {h24}:{0m}")
  end

  def format(datetime, "human") do
    {:ok, Fulib.DateTime.format!(datetime, :human)}
  end

  def format(datetime, "utc_strftime") do
    {:ok, Fulib.DateTime.format!(datetime, :utc_strftime)}
  end

  def format(datetime, "timestamp") do
    {:ok, datetime |> Timex.to_unix()}
  end

  def format(datetime, format) do
    Timex.format(datetime, format)
  end
end
