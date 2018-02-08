defmodule Phoenix.PubSub.Nats do
  use Supervisor
  require Logger

  @pool_size 5

  @moduledoc """
  The Supervisor for the NATS `Phoenix.PubSub` adapter
  """

  def start_link(name, opts \\ []) do
    supervisor_name = Module.concat(__MODULE__, name)
    Supervisor.start_link(__MODULE__, [name, opts], name: supervisor_name)
  end

  def init([name, opts]) do
    supervisor_name = Module.concat(__MODULE__, name)
    pub_conn_pool_base = Module.concat(supervisor_name, PubConnPool)
    conn_pool_base = Module.concat(supervisor_name, ConnPool)

    options = opts[:options] || []
    hosts = options[:hosts] || ["localhost"]
    shard_num = length(hosts)
    host_ring = HashRing.new
    host_ring = HashRing.add_nodes(host_ring, hosts)

    # to make state smaller
    options = List.keydelete(options, :hosts, 0)
    sub_pool_size = opts[:sub_pool_size] || @pool_size
    pub_pool_size = opts[:pub_pool_size] || @pool_size

    ## TODO: set various options from config
    nats_opt = %{
      tcp_opts: [:binary, nodelay: true],
    }

    pub_conn_pools = hosts |> Enum.map(fn(host) ->
      conn_pool_name = create_pool_name(pub_conn_pool_base, host)
      supervisor(Phoenix.PubSub.NatsPubConnSupervisor, [conn_pool_name, pub_pool_size, [Map.merge(nats_opt, extract_host(host))]], id: conn_pool_name)
    end)
    conn_pools = hosts |> Enum.map(fn(host) ->
      conn_pool_name = create_pool_name(conn_pool_base, host)
      conn_pool_opts = [
        name: {:local, conn_pool_name},
        worker_module: Phoenix.PubSub.NatsConn,
        size: sub_pool_size,
        strategy: :fifo,
        max_overflow: 0
      ]
      :poolboy.child_spec(conn_pool_name, conn_pool_opts, [Map.merge(nats_opt, extract_host(host))])
    end)

    dispatch_rules = [
        {:broadcast, Phoenix.PubSub.NatsServer, [name]},
        {:subscribe, Phoenix.PubSub.NatsServer, [name]},
        {:unsubscribe, Phoenix.PubSub.NatsServer, [name]},
      ]

    children = pub_conn_pools ++ conn_pools ++ [
      supervisor(Phoenix.PubSub.LocalSupervisor, [name, 1, dispatch_rules]),
      worker(Phoenix.PubSub.NatsServer,
            [name, pub_conn_pool_base, pub_pool_size, conn_pool_base,
             options ++ [shard_num: shard_num, host_ring: host_ring]])
    ]
    supervise children, strategy: :one_for_one
  end

  def target_shard_host(host_ring, topic) do
    HashRing.key_to_node(host_ring, topic)
  end

  def create_pool_name(pool_base, host) do
    host = String.replace(host, ":", "_")
    Module.concat([pool_base, "_#{host}"])
  end

  def create_pub_conn_name(pool_base, seq) do
    Module.concat([pool_base, "_#{seq}"])
  end

  def get_pub_conn_name(pool_base, topic, size) do
    seq = :erlang.phash2(topic, size)
    create_pub_conn_name(pool_base, seq)
  end

  defp extract_host(host_config) do
    split = String.split(host_config, ":")
    if Enum.count(split) == 1 do
      %{host: to_char_list(List.first(split))}
    else
      %{host: to_char_list(List.first(split)), port: String.to_integer(List.last(split))}
    end
  end

  def with_conn(pool_name, fun) when is_function(fun, 1) do
    case get_conn(pool_name, 0, @pool_size) do
      {:ok, conn}      -> fun.(conn)
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_conn(pool_name, retry_count, max_retry_count) do
    case :poolboy.transaction(pool_name, &GenServer.call(&1, :conn)) do
      {:ok, conn}      -> {:ok, conn}
      {:error, _reason} when retry_count < max_retry_count ->
        get_conn(pool_name, retry_count + 1, max_retry_count)
      {:error, reason} -> {:error, reason}
    end
  end

end
