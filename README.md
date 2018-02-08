Phoenix Pubsub - Nats Adapter
=================================

NATS adapter for the Phoenix framework PubSub layer.

## Usage

Add `phoenix_pubsub_nats` as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:phoenix_pubsub_nats, git: "https://github.com/mtokioka/phoenix_pubsub_nats.git"}]
end
```

You should also update your application list to include `:phoenix_pubsub_nats`:

```elixir
def application do
  [applications: [:phoenix_pubsub_nats]]
end

```

Edit your Phoenix application Endpoint configuration:

      config :my_app, MyApp.Endpoint,
        ...
        pubsub: [name: MyApp.PubSub,
                 adapter: Phoenix.PubSub.Nats,
                 options: [hosts: ["localhost"]]


The following options are supported:

      * `hosts` - The hostnames of the broker(defaults to [\"localhost:4222\"]);
      * `sub_pool_size` - Number of active connections to the broker for subscriber(defaults to 5);
      * `pub_pool_size` - Number of active connections to the broker for publisher(defaults to 5);


## Notes
* https://github.com/mtokioka/phoenix_pubsub_rabbitmq/tree/bk_hosts is the base of this code
* Can be used when multiple brokers are needed for scaling
* Use NATS routing mechanism, delivering a message directly to a consumer process
* You should add handle_out def to channel module.

```elixir
  def handle_out(type, payload, socket) do
    push socket, type, payload
    {:noreply, socket}
  end
```

