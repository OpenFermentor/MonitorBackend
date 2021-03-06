defmodule BioMonitor.SensorManager do
  @moduledoc """
    Wrapper module around all serial communication with
    all sensors using a SerialMonitor instance.
  """
  alias BioMonitor.SerialMonitor

  # Name used for the arduino board.
  @arduino_gs ArduinoGenServer

  @doc """
    Helper to expose arduino's serial monitor identifier.
  """
  def arduino_gs_id, do: @arduino_gs

  @doc """
    Adds all sensors specified in the config file to the
    SerialMonitor.
  """
  def start_sensors do
    with sensor_specs = Application.get_env(
        :bio_monitor,
        BioMonitor.SensorManager
      ),
      false <- sensor_specs == nil,
      arduino_spec <- process_specs(sensor_specs[:arduino]),
      :ok <- SerialMonitor.set_port(
          @arduino_gs,
          arduino_spec.port,
          arduino_spec.speed
        )
    do
      #Register sensors here.
      SerialMonitor.add_sensors(@arduino_gs, arduino_spec[:sensors])
      {:ok, "Sensor ready"}
    else
      {:error, _} ->
        {:error, "Hubo un error al conectarse con la placa."}
      _ ->
        {:error, "Error al procesar la configuración del sistema."}
    end
  end

  @doc """
    Fetch the ph value from the sensor.
  """
  def get_ph do
    case get_readings() do
      {:ok, readings} -> {:ok, readings[:ph]}
      _ -> {:error, "Error al obtener el Ph."}
    end
  end

  @doc """
    sets the offset of the ph sensor for calibration
  """
  def calibratePh(type) do
    case send_and_read(:ph, "CP #{type}") do
      {:ok, _result} -> :ok
      {:error, message, _description} -> {:error, message}
    end
  end

  @doc """
    sets on the acid pump to drop.
  """
  def pump_acid() do
    case send_and_read(:ph, "SP 0 1:185,0:15,2:100,0") do
      {:ok, _result} -> :ok
      {:error, message, _description} -> {:error, message}
    end
  end

  @doc """
    sets on the base pump to drop.
  """
  def pump_base() do
    case send_and_read(:ph, "SP 1 1:255,0:15,2:100,0") do
      {:ok, _result} -> :ok
      {:error, message, _description} -> {:error, message}
    end
  end


  @doc """
    pumps through the third bomb any substance that
    the operator has set up for a time interval.
  """
  def pump_trigger(for_seconds) do
    case send_and_read(:ph, "SP 2 1:#{for_seconds},0") do
      {:ok, _result} -> :ok
      {:error, message, _description} -> {:error, message}
    end
  end

  @doc """
    pushes acid through the pump
  """
  def push_acid() do
    ## TODO, change this values to the real ones
    case send_and_read(:ph, "SP 0 1:4000,0") do
      {:ok, _result} -> :ok
      {:error, message, _description} -> {:error, message}
    end
  end

  @doc """
    pushes base through the pump
  """
  def push_base() do
    ## TODO, change this values to the real ones
    case send_and_read(:ph, "SP 1 1:4000,0") do
      {:ok, _result} -> :ok
      {:error, message, _description} -> {:error, message}
    end
  end

  @doc """
    Get the status of each sensor
  """
  def get_sensors_status() do
    case send_and_read(:temp, "GS") do
      {:ok, result} -> parse_sensors_status(result)
      {:error, message, _description} -> {:error, message}
    end
  end

  @doc """
    Fetchs all readings from the SerialMonitors and parse them.
  """
  def get_readings do
    with {:ok, arduino_readings} <- SerialMonitor.get_readings(@arduino_gs),
      {:ok, temp} <- parse_reading(arduino_readings[:temp]),
      {:ok, ph} <- parse_reading(arduino_readings[:ph])
    do
      IO.puts "~~~~~~~~~~~~~~~~~~~~~"
      IO.puts "~~Temp is: #{temp}~~~"
      IO.puts "~~Ph is: #{ph}~~~~~~~"
      IO.puts "~~~~~~~~~~~~~~~~~~~~~"
      {:ok, %{temp: temp, ph: ph}}
    else
      {:error, message} ->
        {:error, "Hubo un error al obtener las lecturas: #{message}"}
      _ ->
        {:error, "Error inesperado, por favor revise la conexión con la placa."}
    end
  end

  @doc """
    Sends a command for an specific sensor.
    sensor should be one of the previously reigstered sensors.

    example send_command(:temp, "GT")
    returns:
      * {:ok, result}
      * {:error, message}
  """
  def send_command(sensor, command) do
    with {:ok, gs_name} <- gs_name_for_sensor(sensor),
      {:ok, result} <- SerialMonitor.send_command(gs_name, command)
    do
      {:ok, result}
    else
      {:error, message} ->
        {:error, "Error al enviar instrucción.", message}
      :error ->
        {:error, "Ningún sensor concuerda con el puerto."}
    end
  end

  @doc """
    Sends a command for an specific sensor and reads the response.
    sensor should be one of the previously reigstered sensors.

    example send_command(:temp, "GT")
    returns:
      * {:ok, result}
      * {:error, message}
  """
  def send_and_read(sensor, command) do
    with {:ok, gs_name} <- gs_name_for_sensor(sensor),
      {:ok, result} <- SerialMonitor.send_and_read(gs_name, command)
    do
      {:ok, result}
    else
      {:error, message} ->
        {:error, "Error al enviar el comando para el sensor #{sensor}.", message}
      _ ->
        {:error, "No hay ninguún sensor conectado para #{sensor}"}
    end
  end

  #Procesess the keyword list returned from the config file to a
  #list of maps to send to the SerialMonitor with the following format:
  # [
  # %{
  #   port: "dummy port",
  #   sensors: [temp: "GT, ph: "GP"],
  #   speed: 9600
  #  }
  #]
  defp process_specs(sensor_spec) do
    %{
      port: sensor_spec[:port],
      speed: sensor_spec[:speed],
      sensors: sensor_spec[:sensors]
    }
  end

  defp parse_reading(reading) do
    case reading do
      nil -> {:error, "No se pudo obtener la lectura"}
      "ERROR" -> {:error, "Error interno de la placa"}
      {:error, message} -> {:error, message}
      reading -> case Float.parse(reading) do
        {parsed_reading, _} -> {:ok, parsed_reading}
        _ -> {:error, "Hubo un error al conectarse con la placa"}
      end
    end
  end

  defp parse_sensors_status(response) do
    case response do
      "ERROR" -> {:error, "Error interno de la placa"}
      response ->
        strings = String.split(response, ",")
          |> Enum.map(fn val ->
            String.split(val, ":")
          end)
        {
          :ok,
         %{
          pumps: strings |> Enum.at(0) |> Enum.at(1),
          ph: strings |> Enum.at(1) |> Enum.at(1),
          temp: strings |> Enum.at(2) |> Enum.at(1)
          }
        }
    end
  end

  defp gs_name_for_sensor(sensor) do
    case sensor do
      :temp -> {:ok, @arduino_gs}
      :ph -> {:ok, @arduino_gs}
      :density -> {:ok, @arduino_gs}
      _ -> :error
    end
  end

end
