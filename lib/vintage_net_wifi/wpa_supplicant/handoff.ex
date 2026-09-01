# SPDX-FileCopyrightText: 2026 Density
#
# SPDX-License-Identifier: Apache-2.0

defmodule VintageNetWiFi.WPASupplicant.Handoff do
  @moduledoc false

  alias VintageNet.Command
  alias VintageNetWiFi.WPASupplicantLL

  require Logger

  @spec install(Path.t(), iodata(), Path.t() | nil, String.t() | nil) ::
          :ok | {:error, term()}
  def install(config_path, config_contents, mac_path, mac_address) do
    with :ok <- atomic_write(config_path, config_contents) do
      install_mac(mac_path, mac_address)
    end
  end

  @spec remove(Path.t(), Path.t() | nil) :: :ok
  def remove(config_path, mac_path) do
    remove_file(config_path)
    remove_file(mac_path)
    :ok
  end

  @spec stop_and_remove([Path.t()], Path.t(), Path.t() | nil) :: :ok | {:error, term()}
  def stop_and_remove(control_paths, config_path, mac_path) do
    with :ok <- stop_if_running(control_paths) do
      remove(config_path, mac_path)
    end
  end

  @spec ensure_mac(VintageNet.ifname(), String.t(), [Path.t()]) :: :ok | {:error, term()}
  def ensure_mac(ifname, mac_address, control_paths) do
    case current_mac(ifname) do
      {:ok, ^mac_address} ->
        :ok

      _ ->
        with :ok <- stop_prestarted(control_paths) do
          set_mac(ifname, mac_address)
        end
    end
  end

  defp atomic_write(path, contents) do
    temporary_path = "#{path}.tmp.#{System.unique_integer([:positive])}"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(temporary_path, contents, [:binary, :sync]),
         :ok <- File.chmod(temporary_path, 0o600),
         :ok <- File.rename(temporary_path, path) do
      :ok
    else
      error ->
        remove_file(temporary_path)
        error
    end
  end

  defp install_mac(nil, _mac_address), do: :ok

  defp install_mac(mac_path, nil) do
    remove_file(mac_path)
    :ok
  end

  defp install_mac(mac_path, mac_address), do: atomic_write(mac_path, [mac_address, "\n"])

  defp current_mac(ifname) do
    case File.read("/sys/class/net/#{ifname}/address") do
      {:ok, mac_address} -> {:ok, mac_address |> String.trim() |> String.downcase()}
      error -> error
    end
  end

  defp stop_prestarted(control_paths) do
    case Enum.find(Enum.reverse(control_paths), &File.exists?/1) do
      nil ->
        :ok

      control_path ->
        result =
          with {:ok, ll} <-
                 WPASupplicantLL.start_link(path: control_path, notification_pid: self()) do
            response = WPASupplicantLL.control_request(ll, "TERMINATE")
            GenServer.stop(ll)
            response
          end

        case result do
          {:ok, <<"OK", _rest::binary>>} -> wait_for_exit(control_paths, 2_000)
          error -> error
        end
    end
  end

  defp stop_if_running(control_paths) do
    case wait_for_exit(control_paths, 100) do
      :ok -> :ok
      {:error, :prestarted_wpa_supplicant_did_not_exit} -> stop_prestarted(control_paths)
    end
  end

  defp wait_for_exit(_control_paths, time_left) when time_left <= 0,
    do: {:error, :prestarted_wpa_supplicant_did_not_exit}

  defp wait_for_exit(control_paths, time_left) do
    if Enum.any?(control_paths, &File.exists?/1) do
      Process.sleep(50)
      wait_for_exit(control_paths, time_left - 50)
    else
      :ok
    end
  end

  defp set_mac(ifname, mac_address) do
    _ = Command.cmd("ip", ["link", "set", ifname, "down"])

    case Command.cmd("ip", ["link", "set", ifname, "address", mac_address]) do
      {_output, 0} ->
        :ok

      {output, status} ->
        Logger.error(
          "vintage_net_wifi: failed to set #{ifname} MAC to #{mac_address}: " <>
            "exit #{status}: #{inspect(output)}"
        )

        {:error, :mac_address_failed}
    end
  end

  defp remove_file(nil), do: :ok

  defp remove_file(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end
end
