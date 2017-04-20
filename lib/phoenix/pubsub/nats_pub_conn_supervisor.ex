defmodule Phoenix.PubSub.NatsPubConnSupervisor do
  use Supervisor
  alias Phoenix.PubSub.Nats

  def start_link(server, pool_size, opts) do
    Supervisor.start_link(__MODULE__, [server, pool_size, opts])
  end

  def init([server, pool_size, opts]) do
    children = for shard <- 0..(pool_size - 1) do
      name = Nats.create_pub_conn_name(server, shard)
      worker(Phoenix.PubSub.NatsConn, [opts, name], id: name)
    end
    supervise(children, strategy: :one_for_one)
  end

end
