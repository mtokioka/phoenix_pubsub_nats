defmodule Phoenix.PubSub.NatsServer do
  use GenServer
  alias Phoenix.PubSub.Nats
  alias Phoenix.PubSub.NatsConsumer, as: Consumer
  require Logger

  @moduledoc """
  `Phoenix.PubSub` adapter for NATS
  """

  def start_link(server_name, pub_conn_pool_base, pub_conn_pool_size, conn_pool_base, opts) do
    GenServer.start_link(__MODULE__, [server_name, pub_conn_pool_base, pub_conn_pool_size, conn_pool_base, opts], name: server_name)
  end

  @doc """
  Initializes the server.

  """
  def init([_server_name, pub_conn_pool_base, pub_conn_pool_size, conn_pool_base, opts]) do
    Process.flag(:trap_exit, true)
    ## TODO: make state compact
    {:ok, %{cons: :ets.new(:rmq_cons, [:set, :private]),
            subs: :ets.new(:rmq_subs, [:set, :private]),
            pub_conn_pool_base: pub_conn_pool_base,
            pub_conn_pool_size: pub_conn_pool_size,
            conn_pool_base: conn_pool_base,
            node_ref: :crypto.strong_rand_bytes(16),
            opts: opts}}
  end

  def subscribe(server_name, pid, topic, opts) do
    GenServer.call(server_name, {:subscribe, pid, topic, opts})
  end
  def unsubscribe(server_name, pid, topic) do
    GenServer.call(server_name, {:unsubscribe, pid, topic})
  end
  def broadcast(server_name,from_pid, topic, msg) do
    GenServer.call(server_name, {:broadcast, from_pid, topic, msg})
  end

  def handle_call({:subscribe, pid, topic, opts}, _from, state) do
    link = Keyword.get(opts, :link, false)

    subs_list = :ets.lookup(state.subs, topic)
    has_key = case subs_list do
                [] -> false
                [{^topic, pids}] -> Enum.find_value(pids, false, fn(x) -> elem(x, 0) == pid end)
              end

    unless has_key do
      pool_host      = Nats.target_shard_host(state.opts[:host_ring], topic)
      conn_pool_name = Nats.create_pool_name(state.conn_pool_base, pool_host)
      {:ok, consumer_pid} = Consumer.start(conn_pool_name,
                                           topic,
                                           pid,
                                           state.node_ref,
                                           link)
      Process.monitor(consumer_pid)

      if link, do: Process.link(pid)

      :ets.insert(state.cons, {consumer_pid, {topic, pid}})
      pids = case subs_list do
        []                -> []
        [{^topic, pids}]  -> pids
      end
      :ets.insert(state.subs, {topic, pids ++ [{pid, consumer_pid}]})

      {:reply, :ok, state}
    end
  end

  def handle_call({:unsubscribe, pid, topic}, _from, state) do
    case :ets.lookup(state.subs, topic) do
      [] ->
        {:reply, :ok, state}
      [{^topic, pids}] ->
        case Enum.find(pids, false, fn(x) -> elem(x, 0) == pid end) do
          nil ->
            {:reply, :ok, state}
          {^pid, consumer_pid} ->
            :ok = Consumer.stop(consumer_pid)
            delete_subscriber(state.subs, pid, topic)

            {:reply, :ok, state}
        end
    end
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:subscribers, topic}, _from, state) do
    case :ets.lookup(state.subs, topic) do
      []                -> {:reply, [], state}
      [{^topic, pids}]  -> {:reply, Enum.map(pids, fn(x) -> elem(x, 0) end), state}
    end
  end

  def handle_call({:broadcast, from_pid, topic, msg}, _from, state) do
    pool_host = Nats.target_shard_host(state.opts[:host_ring], topic)
    pool_name = Nats.create_pool_name(state.pub_conn_pool_base, pool_host)
    conn_name = Nats.get_pub_conn_name(pool_name, topic, state.pub_conn_pool_size)
    case GenServer.call(conn_name, :conn) |> IO.inspect do
      {:ok, conn}       ->
        case Gnat.pub(conn, topic |> IO.inspect, :erlang.term_to_binary({state.node_ref, from_pid, msg}) |> IO.inspect) do
          :ok               -> {:reply, :ok, state}
          {:error, reason}  -> {:reply, {:error, reason}, state}
        end
      {:error, reason}  -> {:reply, {:error, reason}, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid,  _reason}, state) do
    state =
      case :ets.lookup(state.cons, pid) do
        [] -> state
        [{^pid, {topic, sub_pid}}] ->
          :ets.delete(state.cons, pid)
          delete_subscriber(state.subs, sub_pid, topic)

          state
      end
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    # Ignore subscriber exiting; the Consumer will monitor it
    {:noreply, state}
  end

  defp delete_subscriber(subs, pid, topic) do
    case :ets.lookup(subs, topic) do
      []                ->
        subs
      [{^topic, pids}]  ->
        remain_pids = List.keydelete(pids, pid, 0)
        if length(remain_pids) > 0 do
          :ets.insert(subs, {topic, remain_pids})
        else
          :ets.delete(subs, topic)
        end
        subs
    end
  end

end
