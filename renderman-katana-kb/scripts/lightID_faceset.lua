-- lightID_faceset.lua  (OpScript, Lua)
-- Per-faceset "UV-style" ID color: the gradient over the PARENT MESH's own bounding box,
-- sampled at each faceset's vertex centroid.  R = left->right, G = bottom->top, B = depth,
-- all in the mesh's local space -> one flat color per faceset, immune to the asset's xform.
--
-- Production context: hundreds of bulbs as facesets (piece_N) on ONE mesh; comp keys bulbs
-- by color and drives flashing patterns without re-rendering.  Replaces Cryptomatte
-- (random colors) with a spatially-ordered, quantised-by-construction ID.
--
-- CEL:  .../C_bulbGlass_geo_0Shape/piece_*          (facesets only; the op guards on type)
-- No user parameters.  Pair with lightID_splice.lua + a userColor channel/ROD.
-- Notes:
--   * Works because all facesets share one mesh; split across meshes you'd need a shared frame.
--   * Written as a TYPED user attribute (GroupBuilder type=color) - the form PxrAttribute reads.
--   * Two facesets per bulb (inner/outer) agree on u,v to 4 decimals; w differs slightly.
--   * Output filter: max (not antialiased) keeps IDs pure at silhouettes; per-channel max can
--     mix colors where two DIFFERENT bulbs overlap in a pixel - key with tolerance in comp.

local typeAttr = Interface.GetAttr("type")
if not typeAttr or typeAttr:getValue() ~= "faceset" then return end

local me   = Interface.GetOutputLocationPath()
local mesh = me:match("^(.*)/[^/]+$")

local bAttr     = Interface.GetBoundAttr(mesh)
local facesAttr = Interface.GetAttr("geometry.faces")
local P     = Interface.GetAttr("geometry.point.P", mesh)
local sIdx  = Interface.GetAttr("geometry.poly.startIndex", mesh)
local vList = Interface.GetAttr("geometry.poly.vertexList", mesh)
if not (bAttr and facesAttr and P and sIdx and vList) then
    print("lightID: missing data at " .. me); return
end
local b = bAttr:getNearestSample(0)                          -- xmin,xmax,ymin,ymax,zmin,zmax
local faces, pts  = facesAttr:getNearestSample(0), P:getNearestSample(0)
local start, verts = sIdx:getNearestSample(0), vList:getNearestSample(0)

-- centroid of this faceset's unique vertices (mesh-local)
local seen, sx, sy, sz, n = {}, 0, 0, 0, 0
for _, f in ipairs(faces) do
    for k = start[f + 1], start[f + 2] - 1 do               -- startIndex is 0-based
        local v = verts[k + 1]
        if not seen[v] then
            seen[v] = true
            sx, sy, sz = sx + pts[v*3 + 1], sy + pts[v*3 + 2], sz + pts[v*3 + 3]
            n = n + 1
        end
    end
end
if n == 0 then return end

local function norm(x, a, c) if c - a < 1e-9 then return 0 end return (x - a) / (c - a) end
local u = norm(sx / n, b[1], b[2])
local v = norm(sy / n, b[3], b[4])
local w = norm(sz / n, b[5], b[6])

local gb = GroupBuilder()
gb:set("type",  StringAttribute("color"))
gb:set("value", FloatAttribute({u, v, w}, 3))
Interface.SetAttr("prmanStatements.attributes.user.lightID", gb:build())

print(string.format("lightID %-10s u=%.4f v=%.4f w=%.4f", me:match("[^/]+$"), u, v, w))
