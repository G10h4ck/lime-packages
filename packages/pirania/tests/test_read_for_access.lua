local test_utils = require 'tests.utils'
local utils = require('lime.utils')
local read_for_access = require('read_for_access.read_for_access')
local CONFIG_PATH = "./packages/pirania/files/etc/config/pirania"

local current_time_s = 1008513158
local uci

describe('read_for_access tests #readforaccess', function()
    local snapshot -- to revert luassert stubs and spies

    it('saves authorized macs with configurable duration', function()
        stub(os, 'execute', function() end)
        local duration_m = uci:get('pirania', 'read_for_access', 'duration_m')
        read_for_access.authorize_mac('AA:BB:CC:DD:EE:FF')
        local auth_macs = read_for_access.get_authorized_macs()
        assert.is.equal(1, utils.tableLength(auth_macs))
        assert.is.equal('AA:BB:CC:DD:EE:FF', auth_macs[1])
        current_time_s = 1008513158 + (duration_m * 60) + 1
        auth_macs = read_for_access.get_authorized_macs()
        assert.is.equal(0, utils.tableLength(auth_macs))
    end)

    it('calls captive-portal-update on authorize_mac', function()
        stub(os, 'execute', function() end)
        read_for_access.authorize_mac('AA:BB:CC:DD:EE:FF')
        assert.stub(os.execute).was_called_with('/usr/bin/captive-portal update')
    end)

    before_each('', function()
        snapshot = assert:snapshot()
        local tmp_dir = test_utils.setup_test_dir()
        read_for_access.set_workdir(tmp_dir)
        uci = test_utils.setup_test_uci()
        local default_cfg = io.open(CONFIG_PATH):read("*all")
        test_utils.write_uci_file(uci, 'pirania', default_cfg)
        stub(os, "time", function () return current_time_s end)
    end)

    after_each('', function()
        snapshot:revert()
        test_utils.teardown_test_dir()
        test_utils.teardown_test_uci(uci)
    end)

end)
