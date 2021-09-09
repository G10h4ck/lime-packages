local test_utils = require 'tests.utils'
local fs = require("nixio.fs")

local config = require('voucher.config')
require('packages/pirania/tests/pirania_test_utils').fake_for_tests()
local vouchera = require('voucher.vouchera')
local utils = require('voucher.utils')


function utils.log(...)
    print(...)
end

local current_time_s = 1008513158

describe('Vouchera tests #vouchera', function()
    local snapshot -- to revert luassert stubs and spies
    it('vouchera init empty', function()
        vouchera.init()
        assert.is.equal(0, #vouchera.vouchers)
    end)

    it('vouchera init with broken database does not crash', function()
        os.execute("mkdir /tmp/pirania_vouchers; echo '{asdasd,,,asd.' > /tmp/pirania_vouchers/broken.json")
        vouchera.init()
        assert.is.equal(0, #vouchera.vouchers)
    end)

    it('init and compare vouchers', function()
        vouchera.init()
        local v = {name='myvoucher', code='secret_code', creation_date=current_time_s}
        local voucher_a = vouchera.voucher(v)
        local voucher_b = vouchera.voucher(v)
        v.name = 'othername'
        local voucher_c = vouchera.voucher(v)
        v.name, v.code = 'myvoucher', 'othercode'
        local voucher_d = vouchera.voucher(v)
        v.code = 'myvoucher'
        local voucher_e = vouchera.voucher(v)
        local voucher_f = vouchera.voucher({name='myvoucher', code='secret_code', mod_counter=2, creation_date=current_time_s})
        local voucher_g = vouchera.voucher({name='myvoucher', code='secret_code', mod_counter=3, creation_date=current_time_s})

        assert.is_not_nil(voucher_a)
        assert.is.equal(voucher_a, voucher_b)
        assert.is.not_equal(voucher_a, voucher_c)
        assert.is.not_equal(voucher_a, voucher_d)
        assert.is.not_equal(voucher_a, voucher_e)
        assert.is.not_equal(voucher_a, voucher_f)
        assert.is.not_equal(voucher_f, voucher_g)

        local voucher_h = vouchera.voucher({name='myvoucher', code='secret_code', id='foo', duration_m=100, creation_date=current_time_s})
        local voucher_i = vouchera.voucher({name='myvoucher', code='secret_code', id='foo', duration_m=100, creation_date=current_time_s})
        local voucher_j = vouchera.voucher({name='myvoucher', code='secret_code', id='bar', duration_m=100, creation_date=current_time_s})
        assert.is.equal(voucher_h, voucher_i)
        assert.is.not_equal(voucher_h, voucher_j)
    end)

    it('Rename vouchers', function()
        vouchera.init()
        local voucher = vouchera.add({name='myvoucher', code='secret_code'})
        assert.is.equal(1, voucher.mod_counter)
        vouchera.rename(voucher.id, 'newname')
        assert.is.equal('newname', voucher.name)
        assert.is.equal(2, voucher.mod_counter)
    end)

    it('vouchera create and reload database', function()
        vouchera.init()
        local voucher = vouchera.add({id='myvoucher', name='foo', code='secret_code'})
        assert.is.equal('myvoucher', voucher.id)
        assert.is.equal('foo', voucher.name)
        assert.is.equal('secret_code', voucher.code)
        assert.is_nil(voucher.mac)
        assert.is.equal(current_time_s, voucher.creation_date)

        v1 = vouchera.get_by_id('myvoucher')
        vouchera.init()
        v2 = vouchera.get_by_id('myvoucher')
        assert.is.equal(v1, v2)
        assert.is.not_nil(v1)
    end)

    it('activate vouchers', function()
        vouchera.init()

        assert.is_false(vouchera.is_mac_authorized("aa:bb:cc:dd:ee:ff"))
        assert.is_false(vouchera.is_activable('secret_code'))

        local voucher = vouchera.add({name='myvoucher', code='secret_code', duration_m=100})
        assert.is.equal(1, voucher.mod_counter)
        assert.is.not_false(vouchera.is_activable('secret_code'))
        assert.is_false(vouchera.is_active(voucher))
        assert.is.not_false(vouchera.activate('secret_code', "aa:bb:cc:dd:ee:ff"))

        assert.is.equal(2, voucher.mod_counter)
        assert.is.equal(current_time_s, voucher.activation_date)
        assert.is_false(vouchera.is_activable('secret_code'))
        assert.is_true(vouchera.is_active(voucher))
        assert.is_true(vouchera.is_mac_authorized("aa:bb:cc:dd:ee:ff"))

        --! let's pretend that the expiration date is in the past now
        stub(os, "time", function () return current_time_s + (101*60) end)
        assert.is_false(vouchera.is_mac_authorized("aa:bb:cc:dd:ee:ff"))
        assert.is_false(vouchera.is_active(voucher))
    end)

    it('vouchera create with duration and activate', function()
        vouchera.init()
        local minutes = 10
        local expiration_date = os.time() + minutes * 60

        local voucher = vouchera.add({name='myvoucher', code='secret_code', duration_m=minutes})
        assert.is_nil(voucher.expiration_date())
        local voucher = vouchera.activate('secret_code', "aa:bb:cc:dd:ee:ff")
        assert.is.equal(expiration_date, voucher.expiration_date())
    end)

    it('deactivate vouchers', function()
        vouchera.init()

        local voucher = vouchera.add({id='myvoucher', name='foo', code='secret_code'})
        assert.is.equal(1, voucher.mod_counter)

        local voucher = vouchera.activate('secret_code', "aa:bb:cc:dd:ee:ff")
        assert.is.not_false(voucher)
        assert.is_true(vouchera.is_mac_authorized("aa:bb:cc:dd:ee:ff"))
        assert.is.equal(2, voucher.mod_counter)

        local ret = vouchera.deactivate('myvoucher')
        assert.is.equal(3, voucher.mod_counter)
        assert.is_nil(voucher.mac)
        assert.is_true(ret)
        assert.is_false(vouchera.is_mac_authorized("aa:bb:cc:dd:ee:ff"))
    end)

    it('test activation deadline', function()
        vouchera.init()
        deadline = current_time_s + 10
        local voucher = vouchera.add({name='myvoucher', code='secret_code', duration_m=100,
                                     activation_deadline=deadline})

        assert.is.not_false(vouchera.activate('secret_code', "aa:bb:cc:dd:ee:ff"))

        local voucher = vouchera.add({name='myvoucher2', code='secret_code2', duration_m=100,
                                     activation_deadline=deadline})
        stub(os, "time", function () return deadline + 1 end)
        assert.is_false(vouchera.activate('secret_code2', "aa:bb:cc:dd:ee:ff"))

    end)

    it('add and remove vouchers', function()
        vouchera.init()

        local voucher = vouchera.add({id='myvoucher', name='foo', code='secret_code'})
        assert.is_true(vouchera.remove_locally('myvoucher'))
        assert.is_nil(vouchera.get_by_id('myvoucher'))
        vouchera.init()
        assert.is_nil(vouchera.get_by_id('myvoucher'))
        assert.is_nil(vouchera.remove_locally('myvoucher'))
    end)

    it('add and remove globally vouchers', function()
        vouchera.init()

        local voucher = vouchera.add({id='myvoucher', name='foo', code='secret_code', duration_m=100})
        assert.is_false(vouchera.should_be_pruned(voucher))
        assert.is_true(vouchera.remove_globally('myvoucher'))
        assert.is_false(vouchera.should_be_pruned(voucher))
        assert.is.equal(0, vouchera.get_by_id('myvoucher').duration_m)
    end)

    it('test automatic pruning of old voucher', function()
        config.prune_expired_for_days = '30'
        vouchera.init()
        local v = vouchera.voucher({id='myvoucher', name='foo', code='secret_code',
                                    duration_m=100, creation_date=current_time_s})
        local voucher = vouchera.add(v)
        vouchera.activate('secret_code', "aa:bb:cc:dd:ee:ff")
        assert.is_not_nil(vouchera.get_by_id('myvoucher'))

        -- voucher is pruned when vouchera is initialized
        stub(os, "time", function () return current_time_s+(31*60*60*24) end)
        vouchera.init()
        assert.is_nil(vouchera.get_by_id('myvoucher'))
    end)

    it('test automatic pruning is not removing a not too old voucher', function()
        config.prune_expired_for_days = '100'
        vouchera.init()
        local some_seconds = 10
        local v = vouchera.voucher({id='myvoucher', name='foo', code='secret_code',
                                    duration_m=100, creation_date=current_time_s})

        local voucher = vouchera.add(v)

        assert.is_not_nil(vouchera.get_by_id('myvoucher'))

        -- voucher is not pruned when vouchera is initialized
        stub(os, "time", function () return current_time_s+(31*60*60*24) end)
        vouchera.init()
        assert.is_not_nil(vouchera.get_by_id('myvoucher'))
    end)

    it('test create', function()
        vouchera.init()
        local base_name = 'foo'
        local qty = 1
        local duration_m = 100
        local created_vouchers = vouchera.create(base_name, qty, duration_m)
        assert.is.equal(#created_vouchers, qty)
        local v = vouchera.get_by_id(created_vouchers[1].id)
        assert.is.not_nil(v)
        assert.is.equal(duration_m, v.duration_m)
        assert.is.equal('foo', v.name)

        local qty = 5
        local duration_m = 100
        local deadline = current_time_s + 10
        local created_vouchers = vouchera.create(base_name, qty, duration_m, deadline)
        assert.is.equal(#created_vouchers, qty)

        local v1 = vouchera.get_by_id(created_vouchers[1].id)
        assert.is.equal('foo-1', v1.name)
        assert.is.equal(deadline, v1.activation_deadline)
        assert.is.equal('string', type(created_vouchers[1].code))
        assert.is.not_equal(created_vouchers[1].code, created_vouchers[2].code)

        local v5 = vouchera.get_by_id(created_vouchers[5].id)
        assert.is.equal('foo-5', v5.name)
    end)

    it('test list_vouchers', function()
        vouchera.init()
        local base_name = 'foo'
        local qty = 5
        local duration_m = 100
        local created_vouchers = vouchera.create(base_name, qty, duration_m)

        local listed = vouchera.list()
        assert.is.equal(qty, #listed)
        assert.is.equal(100, listed[1].duration_m)
        assert.is.equal(100, listed[5].duration_m)
        assert.is_false(listed[1].permanent)
        assert.is_false(listed[1].is_active)
    end)

    before_each('', function()
        snapshot = assert:snapshot()
        stub(os, "time", function () return current_time_s end)
    end)

    after_each('', function()
        snapshot:revert()
        local p = io.popen("rm -rf /tmp/pirania_vouchers")
        p:read('*all')
        p:close()
    end)

end)
