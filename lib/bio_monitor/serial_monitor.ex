defmodule BioMonitor.SerialMonitor do
  use GenServer

  @moduledoc """
    The SerialMonitor is in charge of the serial communication with the sensors
  """

  @name SerialMonitor

  @read_delay_ms 30_000
  @new_line "\n"
  @end_reading "\r\n"

  @wrong_argunment "Wrong argument"
  @unrecognized_command "Unrecognized Command"
  @generic_error "ERROR"

  @error_undefined_sensor "The sensor is undefined"
  @error_sending_command "The command could not be sent"
  @error_connection_reading "There was a connection error while reading data from sensor"

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, [name: @name])
  end

  @doc """
  Returns a list of available ports and the devices connected to them
  """
  def get_ports() do
    GenServer.call(@name, :get_ports)
  end

  @doc """
  Sets the port where the device is connected

  name: The name identifier of the port (use `get_ports/0` to retrieve it)
  speed: The speed of the serial port
  """
  def set_port(name, speed) do
    GenServer.call(@name, {:set_port, %{name: name, speed: speed}})
  end

  @doc """
  Adds the sensors whose information comes through the connected device

  sensors: Key value pair, where the key is an atom representing the type of
           the sensor, and the value is the command to fetch the data

  ## Examples

  add_sensor [temp: "getTemp", ph: "getPh"]
  """
  def add_sensors(sensors) do
    GenServer.call(@name, {:add_sensors, %{sensors: sensors}})
  end

  @doc """
  Retrieves the readings for the registered sensors

  ## Examples
  If :temp and :ph sensors are defined, then the returned value would be:

  {:ok, [temp: "20.75", ph: {:error, "Unrecognized Command"}]}
  """
  def get_readings() do
    GenServer.call(@name, :get_readings)
  end

  @doc """
  Sends a command to the sensor.

  sensor: Atom identifying the sensor for the communication
  command: The String instruction to be sent to the sensor
  """
  def send_command(sensor, command) do
    GenServer.call(@name, {:send_command, %{sensor: sensor, command: command}})
  end

  @doc """
  State structure:
  %{
    serial_pid: The pid of the process that handles serial connectivity
    port: The port information to establish a connection with the device
    sensors: Key value pair, where the key is an atom representing the type of
             the sensor, and the value is the command to fetch the data
  }

  ## Examples

  %{
    serial_pid: 1234,
    port: %{
      name: The name of the serial port where the device is connected
      speed: The speed of the serial port
    }
    sensors: [
      %{temp => "getTemp"},
      %{ph => "getPh"}
    ]
  }
  """
  def init(:ok) do
    {:ok, pid} = Nerves.UART.start_link
    {:ok, %{serial_pid: pid, port: %{}, sensors: []}}
  end

  @doc """
  Lists the available ports in the device with the connected devices information,
  such as manufacter id, etc.
  """
  def handle_call(:get_ports, _from, state) do
    {:reply, {:ok, Nerves.UART.enumerate}, state}
  end

  @doc """
  Sets the port where the device is connected

  name: The name identifier of the port (use `get_ports/3` to retrieve it)
  speed: The speed of the serial port
  """
  def handle_call({:set_port, %{name: name, speed: speed}}, _from, state) do
    result = open_connection state.serial_pid, name, speed
    {:reply, result, %{state | port: %{name: name, speed: speed}}}
  end

  @doc """
  Register the sensors to read and execute commands.
  Data format: %{
    sensors: Key value pair, where the key is an atom representing the type of
             the sensor, and the value is the command to fetch the data
  }

  ## Examples

  [
    %{temp => "getTemp"},
    %{ph => "getPh"}
  ]
  """
  def handle_call({:add_sensors, %{sensors: sensors}}, _from, state) do
    {:reply, :ok, %{state | sensors: sensors}}
  end

  @doc """
  Retrieves a hash of key value pairs containing the readings for each of the
  registered sensors.

  ## Example

  [
    %{temp => 28.0}
    %{ph => 7.1}
  ]
  """
  def handle_call(:get_readings, _from, state) do
    {:reply, {:ok, state |> get_sensor_readings}, state}
  end

  @doc """
  Sends the `command` to the specified registered `sensor`
  """
  def handle_call({:send_command, %{sensor: sensor, command: command}}, _from, state) do
    unless state.sensors |> Keyword.has_key?(sensor) do
      {:reply, {:error, @error_undefined_sensor}, state}
    end
    result = Nerves.UART.write(state.serial_pid, command)
    {:reply, (if result == :ok, do: result, else: {:error, @error_sending_command}), state}
  end

  # Opens the connection to the device in the given port
  #
  # uart_pid: The PID of the Nerves process
  # port: The port where the device is located
  # speed: The speed of the serial port
  defp open_connection(uart_pid, port, speed) do
    Nerves.UART.open(uart_pid, port, speed: speed, active: false)
  end

  # Returns the readings for the registered sensors
  #
  # state: The state of the application
  #
  # Example
  #
  # [
  #   %{temp => "28.0"}
  #   %{ph => "7.1"}
  # ]
  defp get_sensor_readings(state) do
    state.sensors
      |> Enum.map(fn {sensor, read_command} ->
          _ = Nerves.UART.write(state.serial_pid, read_command)
          {sensor, state |> get_sensor_reading |> parse_reading}
         end)
  end

  # Retrieves the reading for the given sensor
  #
  # state: The state of the application
  #
  # Example:
  #
  # "28.0"
  # or
  # :error
  defp get_sensor_reading(state) do
    case Nerves.UART.read(state.serial_pid, @read_delay_ms) do
      {:ok, value} ->
        unless is_binary(value) && String.valid?(value) do
          :error
        end

        if String.contains? value, @new_line do
          value
        else
          result = state |> get_sensor_reading
          if result == :error, do: :error, else: value <> result
        end
      _ ->
        :error
    end
  end

  # Parses the seansor reading to sanitize and account for errors
  #
  # reading: The String reading to parse
  #
  # Example:
  #
  # "28.0"
  # or
  # {:error, "Some error"}
  defp parse_reading(reading) do
    case reading do
      :error ->
        {:error, @error_connection_reading}
      value ->
        value = value |> String.trim_trailing(@end_reading)
        if value |> is_reading_error, do: {:error, value}, else: value
    end
  end

  # Recognizes if the reading is any of the known error messages
  defp is_reading_error(reading) do
    errors = [@unrecognized_command, @wrong_argunment, @generic_error]
    Enum.any?(errors, fn(e) -> String.contains? reading, e end)
  end
end
