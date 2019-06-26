defmodule Phoenix.PubSub.NatsConsumer do
  use GenServer
  alias Phoenix.PubSub.Nats
  require Logger

  def start_link(conn_pool, node_name, topic, pid, node_ref, link) do
    GenServer.start_link(__MODULE__, [conn_pool, node_name, topic, pid, node_ref, link])
  end

  def start(conn_pool, node_name, topic, pid, node_ref, link) do
    GenServer.start(__MODULE__, [conn_pool, node_name, topic, pid, node_ref, link])
  end

  def init([conn_pool, node_name, topic, pid, node_ref, link]) do
    Process.flag(:trap_exit, true)

    if link, do: Process.link(pid)

    case Nats.with_conn(conn_pool, fn conn ->
          {:ok, ref} = Gnat.sub(conn, self(), topic)
          Process.monitor(conn)
          Process.monitor(pid)
          {:ok, conn, ref}
        end) do
      {:ok, conn, ref} ->
        {:ok, %{conn: conn, node_name: node_name, pid: pid, sub_ref: ref, node_ref: node_ref}}
      {:error, :disconnected} ->
        {:stop, :disconnected}
    end
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def handle_call(:stop, _from, %{conn: conn, sub_ref: ref} = state) do
    Gnat.unsub(conn, ref)
    {:stop, :normal, :ok, state}
  end

  def handle_info({:msg, %{body: payload, topic: _, reply_to: _}}, state) do
    {remote_node_ref, node_name, from_pid, msg} = :erlang.binary_to_term(payload)

    if (node_name == :none || node_name == state.node_name) and (from_pid == :none or remote_node_ref != state.node_ref or from_pid != state.pid) do
      send(state.pid, msg)
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, pid, reason}, %{pid: pid} = state) do
    # Subscriber died. link: true
    {:stop, {:shutdown, reason}, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    {:stop, {:shutdown, reason}, state}
  end

  def terminate(_reason, state) do
    try do
      Gnat.unsub(state.conn, state.sub_ref)
    catch
      _, _ -> :ok
    end
  end

end
