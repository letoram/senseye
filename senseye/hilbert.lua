--
-- simple reverse- hilbert to offset,
--
-- requires the bit module in namespace which
-- is included with luajit but not all linked lua versions.
--
local bxor = bit.bxor;
local band = bit.band;

local function rot(n, x, y, rx, ry)
	if (ry == 0) then
		if (rx == 1) then
			x = n-1 - x;
			y = n-1 - y;
		end

		return y, x;
	end

	return x, y;
end

local function hilbert_d2xy(base, ofs)
	local rx;
	local ry;
	local x = 0;
	local y = 0;
	local t = ofs;
	local s = 1;

	while s < base do
		rx = band(1, math.floor((t / 2)));
		ry = band(1, bxor(rx, t));
		x, y = rot(s, x, y, rx, ry);
		x = x + s * rx;
		y = y + s * ry;
		t = math.floor(t / 4);
		s = s * 2;
	end

	return x, y;
end

local luts = {
};

--
-- build and cache a lut for each base we need to go from
-- a point in hilbert space to cartesian, used for meta+
-- motion in hilbert mapping mode.
--
function hilbert_lookup(base, x, y)
	if (luts[base] == nil) then
		local d = {};

		local np = base * base;
		if (bxor == nil) then
			warning("Couldn't generate hilbert LUT, bitoperators " ..
				"missing; built arcan with LuaJit enabled");

			for i=0,np do
				d[i] = 0;
			end
			return 0;
		end

		for i=0,np-1 do
			local x, y = hilbert_d2xy(base, i);
			d[y * base + x] = i;
			write_rawresource(string.format("%d=>%d,%d\n", i, x, y));
		end

		close_rawresource();
		d[0] = 0;
		d[np] = base*base;
		luts[base] = d;
	end
	local rv = luts[base][y * base + x];
	return rv;
end

