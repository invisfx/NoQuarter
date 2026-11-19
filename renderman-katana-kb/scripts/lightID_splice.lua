-- lightID_splice.lua  (OpScript, Lua)
-- Patch a RESOLVED material network at render time: add PxrAttribute(user:<attrName>) and wire
-- it into PxrSurface.userColor, so a per-location user attribute comes out as a matte AOV
-- without anyone editing lookdev's published shader.
--
-- Place AFTER an explicit MaterialResolve (before resolve a location only has materialAssign;
-- material.terminals/nodes don't exist yet and the op silently does nothing).
-- CEL: the mesh AND its facesets - facesets commonly carry their OWN material assignment, so
--      patching only the mesh leaves them unpatched:
--      .../C_bulbGlass_geo_0Shape + .../C_bulbGlass_geo_0Shape/piece_*
-- user.attrName (string, default lightID)
--
-- Output side (nodes): /root prmanGlobalStatements.options.lpe.user4 = "UserColor";
--   PrmanOutputChannelDefine name=lightID type=color
--   source = lpe:nothruput;noinfinitecheck;noclamp;unoccluded;overwrite;CU4L
--   RenderOutputDefine raw / channel lightID / 32-bit / no view transform.
-- Debug ladder when black: hard-set parameters.userColor = (1,0,0) -> red = output side OK,
--   problem is the attribute read; black = U4 registration / LPE / ROD.  Also confirm the bxdf
--   is PxrSurface (userColor exists only there) and the attribute is TYPED color.

local a = Interface.GetOpArg("user.attrName")
local attrName = a and a:getValue() or "lightID"

local term = Interface.GetAttr("material.terminals.prmanBxdf")
if not term then return end
local bxdf = term:getValue()

local conn = "material.nodes." .. bxdf .. ".connections.userColor"
if Interface.GetAttr(conn) then
    print("userColor already connected on " .. Interface.GetOutputLocationPath() .. ", skipped")
    return
end

local n, base = "LGT_" .. attrName .. "Attr", "material.nodes.LGT_" .. attrName .. "Attr."
Interface.SetAttr(base .. "name",    StringAttribute(n))
Interface.SetAttr(base .. "srcName", StringAttribute(n))
Interface.SetAttr(base .. "type",    StringAttribute("PxrAttribute"))
Interface.SetAttr(base .. "target",  StringAttribute("prman"))
Interface.SetAttr(base .. "parameters.varname", StringAttribute(attrName))
Interface.SetAttr(base .. "parameters.type",    StringAttribute("color"))
Interface.SetAttr(conn, StringAttribute("resultRGB@" .. n))
