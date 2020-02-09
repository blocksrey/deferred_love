local mat3 = require("mat3")
local vec3 = require("vec3")



--load in the geometry shader and compositing shader
local geomshader = love.graphics.newShader("geom_pixel_shader.glsl", "geom_vertex_shader.glsl")
local compshader = love.graphics.newShader("comp_pixel_shader.glsl")

--make the buffers
local geombuffer
local compbuffer
local function makebuffers()
	local w, h = love.graphics.getDimensions()

	local depth = love.graphics.newCanvas(w, h, {format = "depth32f";})
	local position = love.graphics.newCanvas(w, h, {format = "rgba32f";})
	local normal = love.graphics.newCanvas(w, h, {format = "rgba32f";})
	local color = love.graphics.newCanvas(w, h)

	geombuffer = {
		depthstencil = depth;
		position,
		normal,
		color,
	}

	local composite = love.graphics.newCanvas(w, h)

	compbuffer = {
		composite,
	}
end

makebuffers()

--this will allow us to compute the frustum transformation matrix once,
--then send it off to the gpu
--width of the screen plane (screen width / screen height)
--height of the screen plane (1 = 90 degree fov)
--near clipping plane distance (positive)
--far clipping plane distance (positive)
--pos (vec3 camera position)
--rot (mat3 camera rotation)
--returns a 4x4 transformation matrix to be passed to the vertex shader
local function getfrusT(width, height, near, far, pos, rot)
	local px, py, pz = pos.x, pos.y, pos.z
	local xx, yx, zx, xy, yy, zy, xz, yz, zz =	rot.xx, -rot.yx, rot.zx,
												rot.xy, -rot.yy, rot.zy,
												rot.xz, -rot.yz, rot.zz
	local xmul = 1/width
	local ymul = 1/height
	local zmul = (far + near)/(far - near)
	local zoff = (2*far*near)/(far - near)
	local rx = px*xx + py*xy + pz*xz
	local ry = px*yx + py*yy + pz*yz
	local rz = px*zx + py*zy + pz*zz
	return {
		xmul*xx, xmul*xy, xmul*xz, -xmul*rx,
		ymul*yx, ymul*yy, ymul*yz, -ymul*ry,
		zmul*zx, zmul*zy, zmul*zz, -zmul*rz - zoff,
		zx,      zy,      zz,      -rz
	}
end


--basic definition
local vertdef = {
	{"VertexPosition", "float", 3},
	{"norm", "float", 3},
	{"VertexColor", "byte", 4},
	{"VertexTexCoord", "float", 2},
}

--will later be replaced with newconvex
local function newtest(r, g, b, a)
	local vertices = {}
	--[[
	local ux, uy, uz = bx - ax, by - ay, bz - az
	local vx, vy, vz = cx - ax, cy - ay, cz - az
	local nx = uy*vz - uz*vy
	local ny = uz*vx - ux*vz
	local nz = ux*vy - uy*vx

	vertices[1] = {ax, ay, az, nx, ny, nz, r, g, b, a, 0, 0}
	vertices[2] = {bx, by, bz, nx, ny, nz, r, g, b, a, 1, 0}
	vertices[3] = {cx, cy, cz, nx, ny, nz, r, g, b, a, 1, 1}
	]]
	local n = 500000--256/4*4096
	for i = 0, n - 1 do--[[256/4*4096]]
		local ox = math.random()*20 - 10
		local oy = math.random()*20 - 10
		local oz = math.random()*20 - 10

		vertices[12*i + 1] = {1 + ox, 0 + oy, 0 + oz, 1, 1, 1, r, g, b, a, 0, 0}
		vertices[12*i + 2] = {0 + ox, 1 + oy, 0 + oz, 1, 1, 1, r, g, b, a, 1, 0}
		vertices[12*i + 3] = {0 + ox, 0 + oy, 1 + oz, 1, 1, 1, r, g, b, a, 0, 1}

		vertices[12*i + 4] = {0 + ox, 0 + oy, 0 + oz, -1, 0, 0, r, g, b, a, 0, 0}
		vertices[12*i + 5] = {0 + ox, 0 + oy, 1 + oz, -1, 0, 0, r, g, b, a, 1, 0}
		vertices[12*i + 6] = {0 + ox, 1 + oy, 0 + oz, -1, 0, 0, r, g, b, a, 0, 1}

		vertices[12*i + 7] = {0 + ox, 0 + oy, 1 + oz, 0, -1, 0, r, g, b, a, 0, 0}
		vertices[12*i + 8] = {0 + ox, 0 + oy, 0 + oz, 0, -1, 0, r, g, b, a, 1, 0}
		vertices[12*i + 9] = {1 + ox, 0 + oy, 0 + oz, 0, -1, 0, r, g, b, a, 0, 1}

		vertices[12*i + 10] = {0 + ox, 1 + oy, 0 + oz, 0, 0, -1, r, g, b, a, 0, 0}
		vertices[12*i + 11] = {1 + ox, 0 + oy, 0 + oz, 0, 0, -1, r, g, b, a, 1, 0}
		vertices[12*i + 12] = {0 + ox, 0 + oy, 0 + oz, 0, 0, -1, r, g, b, a, 0, 1}
		--vertices[12*i + 1] = {ax + math.random(), ay + math.random(), az + math.random(), nx, ny, nz, r, g, b, a, 0, 0}
		--vertices[12*i + 2] = {bx + math.random(), by + math.random(), bz + math.random(), nx, ny, nz, r, g, b, a, 1, 0}
		--vertices[12*i + 3] = {cx + math.random(), cy + math.random(), cz + math.random(), nx, ny, nz, r, g, b, a, 1, 1}
	end

	local mesh = love.graphics.newMesh(vertdef, vertices, "triangles", "dynamic")

	local pos = vec3.null
	local rot = mat3.I
	local scale = vec3.new(1, 1, 1)

	--local changed = false

	local vertT = {
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
	local normT = {
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
	--returns a 4x4 transformation matrix to be passed to the vertex shader
	local function updatetransforms()
		--mat3(scale)*rot
		vertT[1]  = scale.x*rot.xx
		vertT[2]  = scale.y*rot.yx
		vertT[3]  = scale.z*rot.zx
		vertT[4]  = pos.x
		vertT[5]  = scale.x*rot.xy
		vertT[6]  = scale.y*rot.yy
		vertT[7]  = scale.z*rot.zy
		vertT[8]  = pos.y
		vertT[9]  = scale.x*rot.xz
		vertT[10] = scale.y*rot.yz
		vertT[11] = scale.z*rot.zz
		vertT[12] = pos.z
		--transpose(det(vertT)*inverse(vertT))
		normT[1]  = scale.y*scale.z*(rot.yy*rot.zz - rot.yz*rot.zy)
		normT[2]  = scale.y*scale.z*(rot.xz*rot.zy - rot.xy*rot.zz)
		normT[3]  = scale.y*scale.z*(rot.xy*rot.yz - rot.xz*rot.yy)
		normT[5]  = scale.x*scale.z*(rot.yz*rot.zx - rot.yx*rot.zz)
		normT[6]  = scale.x*scale.z*(rot.xx*rot.zz - rot.xz*rot.zx)
		normT[7]  = scale.x*scale.z*(rot.xz*rot.yx - rot.xx*rot.yz)
		normT[9]  = scale.x*scale.y*(rot.yx*rot.zy - rot.yy*rot.zx)
		normT[10] = scale.x*scale.y*(rot.xy*rot.zx - rot.xx*rot.zy)
		normT[11] = scale.x*scale.y*(rot.xx*rot.yy - rot.xy*rot.yx)
	end

	local self = {}

	function self.setpos(newpos)
		changed = true
		pos = newpos
	end

	function self.setrot(newrot)
		changed = true
		rot = newrot
	end

	function self.setscale(newscale)
		changed = true
		scale = newscale
	end

	function self.draw()
		if changed then
			changed = false
			updatetransforms()
		end
		--mesh:setVertex(1, {1 - math.random(), 0 - math.random(), 0 - math.random(), 1, 1, 1, r, g, b, a, 0, 0})
		geomshader:send("vertT", vertT)
		geomshader:send("normT", normT)
		love.graphics.draw(mesh)
	end

	return self
end

love.window.setVSync(false)


love.graphics.setMeshCullMode("front")

local function drawmeshes(frusT, meshes)
	love.graphics.setDepthMode("less", true)
	love.graphics.setCanvas(geombuffer)
	love.graphics.setShader(geomshader)
	love.graphics.clear()
	geomshader:send("frusT", frusT)
	for i = 1, #meshes do
		meshes[i].draw()
	end
	love.graphics.setDepthMode()
	love.graphics.setShader(compshader)
	love.graphics.setCanvas(compbuffer)
	compshader:send("wverts", geombuffer[1])
	compshader:send("wnorms", geombuffer[2])
	love.graphics.draw(geombuffer[3])
	--local w, h = love.graphics.getDimensions()
	--love.graphics.rectangle("fill", 0, 0, w, h)
	love.graphics.setShader()
	love.graphics.setCanvas()
	love.graphics.draw(compbuffer[1])--, 0, h, 0, 1, -1)--just straight up color
end




























love.mouse.setRelativeMode(true)

local near = 1/10
local far = 5000
local pos = vec3.new(0, 0, -5)
local angy = 0
local angx = 0
local sens = 1/256
local speed = 8

function love.keypressed(k)
	if k == "escape" then
		love.event.quit()
	end
end

local function clamp(p, a, b)
	return p < a and a or p > b and b or p
end


local pi = math.pi

function love.mousemoved(px, py, dx, dy)
	angy = angy + sens*dx
	angx = angx + sens*dy
	angx = clamp(angx, -pi/2, pi/2)
end

function love.update(dt)
	local rot = mat3.fromeuleryxz(angy, angx, 0)

	local keyd = love.keyboard.isDown("d") and 1 or 0
	local keya = love.keyboard.isDown("a") and 1 or 0
	local keye = love.keyboard.isDown("e") and 1 or 0
	local keyq = love.keyboard.isDown("q") and 1 or 0
	local keyw = love.keyboard.isDown("w") and 1 or 0
	local keys = love.keyboard.isDown("s") and 1 or 0

	local vel = rot*vec3.new(keyd - keya, keye - keyq, keyw - keys):unit()
	pos = pos + dt*speed*vel
end



local meshes = {}
meshes[1] = newtest(1, 1, 1, 1)


function love.draw()
	local w, h = love.graphics.getDimensions()

	local t = love.timer.getTime()--tick()
	local rot = mat3.fromeuleryxz(angy, angx, 0)
	local frusT = getfrusT(w/h, 1, near, far, pos, rot)


	--[[for i = 1, #meshes do
		meshes[i].setrot(
			unpack(fromangles(t + i/10, 0, 0))
		)
	end]]

	--meshes[1].setrot(mat3.fromeuleryxz(0, 0, 0))

	drawmeshes(frusT, meshes)
	love.graphics.print(tostring(rot))
	--love.graphics.print(love.timer.getFPS())

	--love.window.setTitle(love.timer.getFPS())
end