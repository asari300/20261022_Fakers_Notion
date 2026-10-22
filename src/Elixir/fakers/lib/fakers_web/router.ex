defmodule FakersWeb.Router do
  use FakersWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", FakersWeb do
    pipe_through :api

    get "/pages", PageApiController, :index
    post "/pages", PageApiController, :create
  end

  # それ以外はすべて SPA（/assets/* は手前の Plug.Static が返す）
  scope "/", FakersWeb do
    get "/*path", PageController, :index
  end
end
