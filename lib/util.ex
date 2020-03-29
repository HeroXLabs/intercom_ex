defmodule Intercom.Util do
  @moduledoc false

  @doc """
  Takes a map and turns it into proper query values.
  ## Example
  card_data = %{
    cards: [
      %{
        number: 424242424242,
        exp_year: 2014
      },
      %{
        number: 424242424242,
        exp_year: 2017
      }
    ]
  }
  Intercom.Util.encode_query(card_data) # cards[0][number]=424242424242&cards[0][exp_year]=2014&cards[1][number]=424242424242&cards[1][exp_year]=2017
  """
  @spec encode_query(map) :: String.t()
  def encode_query(map) do
    map |> UriQuery.params() |> URI.encode_query()
  end

  @doc """
  Performs a root-level conversion of map keys from strings to atoms.
  This function performs the transformation safely using `String.to_existing_atom/1`, but this has a possibility to raise if
  there is not a corresponding atom.
  It is recommended that you pre-filter maps for known values before
  calling this function.
  ## Examples
  iex> map = %{
  ...>   "a"=> %{
  ...>     "b" => %{
  ...>       "c" => 1
  ...>     }
  ...>   }
  ...> }
  iex> Intercom.Util.map_keys_to_atoms(map)
  %{
    a: %{
      "b" => %{
        "c" => 1
      }
    }
  }
  """
  def map_keys_to_atoms(m) do
    Enum.into(m, %{}, fn
      {k, v} when is_binary(k) ->
        a = String.to_atom(k)
        {a, v}

      entry ->
        entry
    end)
  end

  def atomize_keys(map = %{}) do
    Enum.into(map, %{}, fn {k, v} -> {atomize_key(k), atomize_keys(v)} end)
  end

  def atomize_keys([head | rest]), do: [atomize_keys(head) | atomize_keys(rest)]
  def atomize_keys(not_a_map), do: not_a_map

  def atomize_key(k) when is_binary(k), do: String.to_atom(k)
  def atomize_key(k), do: k
end
