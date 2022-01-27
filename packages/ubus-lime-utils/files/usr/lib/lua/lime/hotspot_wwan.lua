#!/usr/bin/env lua
--[[
  Copyright (C) 2021 LibreMesh.org
  This is free software, licensed under the GNU AFFERO GENERAL PUBLIC LICENSE Version 3

  Copyright 2021 Santiago Piccinini <spiccinini@altermindi.net>
]]--

local utils = require 'lime.utils'
local config = require 'lime.config'
local iwinfo = require "iwinfo"

local pkg = {}

pkg.DEFAULT_ENCRYPTION = 'psk2'
pkg.DEFAULT_SSID = 'internet'
pkg.DEFAULT_PASSWORD = 'internet'
pkg.DEFAULT_RADIO = 'radio0'

function pkg.generic_section_name(radio_name)
    return 'hotspot_wwan_' .. radio_name
end

function pkg.iface_section_name(radio_name)
    return 'lm_client_wwan_' .. radio_name
end

function pkg.iface_name(radio_name)
    return 'client-wwan-' .. string.sub(radio_name, -1)
end

local gen_cfg = require 'lime.generic_config'

function pkg._apply_change()
    --config.uci_autogen()
    --gen_cfg.do_generic_uci_configs()
    --local uci = config.get_uci_cursor()
    --uci:commit("wireless")
    --uci:load("wireless")
    utils.unsafe_shell("lime-config && wifi reload")
end

--! Create a client connection to a wifi hotspot
function pkg.enable(ssid, password, encryption, radio)
    local uci = config.get_uci_cursor()
    local encryption = encryption or pkg.DEFAULT_ENCRYPTION
    local ssid = ssid or pkg.DEFAULT_SSID
    local password = password or pkg.DEFAULT_PASSWORD
    local radio = radio or pkg.DEFAULT_RADIO
    local iface_section_name = pkg.iface_section_name(radio)

    uci:set(config.UCI_NODE_NAME, pkg.generic_section_name(radio), "generic_uci_config")
    uci:set(config.UCI_NODE_NAME, pkg.generic_section_name(radio), "uci_set", {
        "wireless." .. radio .. ".disabled=0",
        "wireless." .. iface_section_name .. "=wifi-iface",
        "wireless." .. iface_section_name .. ".device=" .. radio,
        "wireless." .. iface_section_name .. ".network=" .. iface_section_name,
        "wireless." .. iface_section_name .. ".mode=sta",
        "wireless." .. iface_section_name .. ".ifname=" .. pkg.iface_name(radio),
        "wireless." .. iface_section_name .. ".ssid=" .. ssid,
        "wireless." .. iface_section_name .. ".encryption=" .. encryption,
        "wireless." .. iface_section_name .. ".key=" .. password,
        "network." .. iface_section_name .. "=interface",
        "network." .. iface_section_name .. ".proto=dhcp",
        }
    )
    uci:commit(config.UCI_NODE_NAME)
    pkg._apply_change()
    return true
end

function pkg.disable(radio)
    local uci = config.get_uci_cursor()
    local radio = radio or pkg.DEFAULT_RADIO

    uci:delete(config.UCI_NODE_NAME, pkg.generic_section_name(radio))
    uci:commit(config.UCI_NODE_NAME)

    pkg._apply_change()
    return true
end

function pkg.status(radio)
    local uci = config.get_uci_cursor()
    local radio = radio or pkg.DEFAULT_RADIO
    local connected = false
    local signal

    local enabled = false

    if uci:get(config.UCI_NODE_NAME, pkg.generic_section_name(radio)) then
        enabled = true
    end

    for mac, station in pairs(iwinfo.nl80211.assoclist(pkg.iface_name(radio))) do
        connected = true
        signal = station['signal']
    end

    return {connected = connected, signal = signal, enabled = enabled}
end


return pkg
