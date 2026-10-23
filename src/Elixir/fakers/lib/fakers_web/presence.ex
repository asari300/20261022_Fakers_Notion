defmodule FakersWeb.Presence do
  @moduledoc """
  文書ごとの参加者とカーソル。meta は `%{name, cursor}`、cursor は
  `nil | %{block, anchor, head}`（anchor と head は yjs の相対位置を base64 にしたもの。サーバは中身を見ない）。
  """
  use Phoenix.Presence, otp_app: :fakers, pubsub_server: Fakers.PubSub
end
