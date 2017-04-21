defmodule Phoenix.PubSub.NatsConn do
  use GenServer
  require Logger

  @reconnect_after_ms 5_000

  @moduledoc """
  Worker for pooled connections to NATS
  """

  @doc """
  Starts the server
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  def start_link(opts, name) do
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def init([opts]) do
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %{opts: opts, status: :disconnected, conn: nil}}
  end

  def handle_call(:conn, _from, %{status: :connected, conn: conn} = status) do
    {:reply, {:ok, conn}, status}
  end

  def handle_call(:conn, _from, %{status: :disconnected} = status) do
    {:reply, {:error, :disconnected}, status}
  end

  def handle_info(:connect, state) do
    case Gnat.start_link(state.opts) do
      {:ok, pid} ->
        {:noreply, %{state | conn: pid, status: :connected}}
      {:error, _reason} ->
        :timer.send_after(@reconnect_after_ms, :connect)
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, _ref, _reason}, %{conn: _pid, status: :connected} = state) do
    Logger.error "lost Nats connection. Attempting to reconnect..."
    :timer.send_after(@reconnect_after_ms, :connect)
    {:noreply, %{state | conn: nil, status: :disconnected}}
  end

  def handle_info({:EXIT, _ref, :shutdown}, %{conn: pid, status: :connected} = state) do
    Gnat.stop(pid)
    {:noreply, %{state | conn: nil, status: :disconnected}}
  end

  def terminate(_reason, %{conn: pid, status: :connected}) do
    try do
      Gnat.stop(pid)
    catch
      _, _ -> :ok
    end
  end
  def terminate(_reason, _state) do
    :ok
  end
end
