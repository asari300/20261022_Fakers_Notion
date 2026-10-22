defmodule FakersWeb.UserSocket do
  use Phoenix.Socket

  # 文書ごとの topic。認証は P4 まで無し
  channel "doc:*", FakersWeb.DocumentChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
