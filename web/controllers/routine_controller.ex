defmodule BioMonitor.RoutineController do
  use BioMonitor.Web, :controller

  alias BioMonitor.Routine
  alias BioMonitor.SyncServer
  @routines_per_page "10"

  def index(conn, params) do
    {routines, rummage} =
      Routine |>
      Rummage.Ecto.rummage(%{
        "paginate" => %{
          "per_page" => @routines_per_page,
          "page" => "#{params["page"] || 1}"
        }
      })
    routines = Repo.all(routines)
    render(conn, "index.json", routine: routines, page_info: rummage)
  end

  def create(conn, %{"routine" => routine_params}) do
    changeset = Routine.changeset(%Routine{}, routine_params)
    case Repo.insert(changeset) do
      {:ok, routine} ->
        SyncServer.send("new_routine", Map.put(routine_params, :uuid, routine.uuid))
        conn
        |> put_status(:created)
        |> put_resp_header("location", routine_path(conn, :show, routine))
        |> render("show.json", routine: routine)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(BioMonitor.ChangesetView, "error.json", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    routine = Repo.get!(Routine, id)
    render(conn, "show.json", routine: routine)
  end

  def update(conn, %{"id" => id, "routine" => routine_params}) do
    routine = Repo.get!(Routine, id)
    changeset = Routine.changeset(routine, routine_params)

    case Repo.update(changeset) do
      {:ok, routine} ->
        SyncServer.send("update_routine", Map.put(routine_params, :uuid, routine.uuid))
        render(conn, "show.json", routine: routine)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(BioMonitor.ChangesetView, "error.json", changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    routine = Repo.get!(Routine, id)
    Repo.delete!(routine)
    SyncServer.send("update_routine", %{"uuid" => routine.uuid})
    send_resp(conn, :no_content, "")
  end

  def stop(conn, _params) do
    BioMonitor.RoutineMonitor.stop_routine()
    send_resp(conn, :no_content, "")
  end

  def start(conn, %{"id" => id}) do
    routine = Repo.get!(Routine, id)
    with running = BioMonitor.RoutineMonitor.is_running?(),
      {:ok, false} <- running,
      :ok <- BioMonitor.RoutineMonitor.start_routine(routine)
    do
      render(conn, "show.json", routine: routine)
    else
      {:error, _, message} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(BioMonitor.ErrorView, "error.json", message: message)
      {:ok, true} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(BioMonitor.RoutineView, "unavailable.json")
      _ ->
        conn
        |> put_status(500)
        |> render(BioMonitor.RoutineView, "500.json")
    end
  end

  def to_csv(conn, %{"routine_id" => id}) do
    routine =
      Routine
      |> Repo.get!(id)
      |> Repo.preload(:readings)

    path = "#{routine.title}_readings.csv"
    file = File.open!(Path.expand(path), [:write, :utf8])

    routine.readings
      |> CSV.encode(headers: [:temp, :ph, :density, :inserted_at])
      |> Enum.each(&IO.write(file, &1))

    conn
      |> put_resp_header("Content-Disposition", "attachment; filename=#{path}")
      |> send_file(200, path)

    File.close(file)
    File.rm(path)
  end

  def restart(conn, _params) do
    BioMonitor.RoutineMonitor.start_loop()
    send_resp(conn, :no_content, "")
  end
end
