-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Global / Persistent configuration management

local defaults = {
	point_size = 1.0,
	hlight_r = 0.0,
	hlight_g = 1.0,
	hlight_b = 0.0,
	msg_timeout = 100,
	map_default = 10,
	pack_default = 20,
	alpha_default = 30,
	sample_default = 256,
	hmatch_pct = 90,
	repeat_period = 50,
	repeat_delay = 100
};

function gconfig_set(key, val)
	if (type(val) ~= type(defaults[key])) then
		warning("gconfig_set(), type mismatch for key: " .. key);
		return;
	end

	defaults[key] = val;
end

function gconfig_get(key)
	return defaults[key];
end

local function gconfig_setup()
	for k,vl in pairs(defaults) do
		local v = get_key(k);
		if (v) then
			if (type(vl) == "number") then
				defaults[k] = tonumber(v);
			else
				defaults[k] = v;
			end
		end
	end
end

function gconfig_shutdown()
	local ktbl = {};

	for k,v in pairs(defaults) do
		ktbl[k] = tostring(v);
	end

	store_key(ktbl);
end

gconfig_setup();
