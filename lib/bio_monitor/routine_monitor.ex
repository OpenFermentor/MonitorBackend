defmodule BioMonitor.RoutineMonitor do
  use GenServer, otp_app: :bio_monitor

  @moduledoc """
    The RoutineMonitor is in charge of controlling the currently running routine.
  """

  @name RoutineMonitor

  alias BioMonitor.Routine
  alias BioMonitor.Reading
  alias BioMonitor.Repo

  # User API
  def start_link() do
    start_server()
  end

  def start_server() do
    GenServer.start_link(__MODULE__, :ok, [name: @name])
  end

  def start_routine(routine) do
    GenServer.call(@name, {:start, routine})
  end

  def stop_routine() do
    GenServer.call(@name, :stop)
  end

  def update_routine(routine) do
    GenServer.call(@name, {:update, routine})
  end

  def is_running?()do
    GenServer.call(@name, :is_running)
  end

  # GenServer Callbacks
  def init(:ok) do
    {:ok, %{:loop => false, :routine => %{}}}
  end

  def handle_call({:start,  routine}, _from, state = %{loop: runLoop, routine: _routine}) do
    case runLoop do
      true ->
        {:reply, :routine_in_progress, state}
      false ->
        schedule_work()
        {:reply, :ok, %{:loop => true, :routine => routine}}
    end
  end

  def handle_call(:stop, _from, _state) do
    {:reply, :ok, %{loop: false, routine: %{}}}
  end

  def handle_call({:update, routine}, _from, _state) do
    {:reply, :ok, %{:loop => true, :routine => routine}}
  end

  def handle_call(:is_running, _from, state = %{loop: runLoop, routine: _routine}) do
    {:reply, {:ok, runLoop}, state}
  end

  def handle_info(:loop, state = %{loop: runLoop, routine: routine}) do
    case runLoop do
      true ->
        routine.id
        |> fetch_reading
        |> process_reading
        schedule_work()
      false ->
        IO.puts 'Loop stopped'
    end
    {:noreply, state}
  end

  def terminate(reason, _state) do
    case reason do
      :normal ->
        IO.puts 'Server terminated normally'
      :shutdown ->
        IO.puts 'Server shutted down'
      _ ->
        IO.puts 'Uknown error'
    end
  end

  # Helpers
  defp schedule_work() do
    Process.send_after(self(), :loop, 1000)
  end

  defp fetch_reading(routine_id) do
    IO.puts 'Fetching reading from sensors.'
    #TODO Do fetching here.
    data = %{}
    with routine = Repo.get(Routine, routine_id),
      true <- routine != nil,
      reading <- Ecto.build_assoc(routine, :readings),
      changeset <- Reading.changeset(reading, data),
      {:ok, reading} <- Repo.insert(changeset)
    do
      {:ok, reading}
    else
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp process_reading({:ok, reading}) do
    #TODO Do any pprocessing and broadcast here.
  end

  defp process_reading({:error, changeset}) do
    #TODO Broadcast errors from here.
  end
end
