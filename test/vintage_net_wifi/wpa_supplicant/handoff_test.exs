# SPDX-FileCopyrightText: 2026 Density
#
# SPDX-License-Identifier: Apache-2.0

defmodule VintageNetWiFi.WPASupplicant.HandoffTest do
  use ExUnit.Case

  alias VintageNetWiFi.WPASupplicant.Handoff

  test "atomically installs private boot config and MAC files and removes them" do
    directory = Path.join("test_tmp", "handoff-#{System.unique_integer([:positive])}")
    config_path = Path.join(directory, "wpa_supplicant.conf.wlan0")
    mac_path = Path.join(directory, "wlan0.mac")

    on_exit(fn -> File.rm_rf(directory) end)

    assert :ok = Handoff.install(config_path, "network={}\n", mac_path, "aa:bb:cc:dd:ee:ff")
    assert File.read!(config_path) == "network={}\n"
    assert File.read!(mac_path) == "aa:bb:cc:dd:ee:ff\n"
    assert private_file?(config_path)
    assert private_file?(mac_path)

    assert :ok = Handoff.install(config_path, "network={updated=1}\n", mac_path, nil)
    assert File.read!(config_path) == "network={updated=1}\n"
    refute File.exists?(mac_path)

    assert :ok = Handoff.remove(config_path, mac_path)
    refute File.exists?(config_path)
    refute File.exists?(mac_path)
  end

  defp private_file?(path) do
    {:ok, stat} = File.stat(path)
    Bitwise.band(stat.mode, 0o777) == 0o600
  end
end
