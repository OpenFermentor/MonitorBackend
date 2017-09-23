defmodule BioMonitor.RoutineView do
  use BioMonitor.Web, :view

  def render("index.json", %{routine: routine, page_info: page_info}) do
    Map.merge(
      %{
        data: render_many(routine, BioMonitor.RoutineView, "routine.json")
      },
      page_info
    )
  end

  def render("show.json", %{routine: routine}) do
    %{data: render_one(routine, BioMonitor.RoutineView, "routine.json")}
  end

  def render("routine.json", %{routine: routine}) do
    %{
      id: routine.id,
      uuid: routine.uuid,
      title: routine.title,
      strain: routine.strain,
      medium: routine.medium,
      target_temp: routine.target_temp,
      target_ph: routine.target_ph,
      target_co2: routine.target_co2,
      target_density: routine.target_density,
      estimated_time_seconds: routine.estimated_time_seconds,
      extra_notes: routine.extra_notes,
      started: routine.started,
      started_date: routine.started_date,
      inserted_at: routine.inserted_at,
      updated_at: routine.updated_at,
    }
  end

  def render("unavailable.json", _assigns) do
    %{error: "El fermentador está trabajando en otro experimento en este momento."}
  end

  def render("already_run.json", _assigns) do
    %{error: "El experimento ya fue corrido."}
  end
end
