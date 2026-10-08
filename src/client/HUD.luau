-- The HUD: phones/tablets get the touch layout (HUDMobile), computers the
-- classic desktop layout (HUDDesktop). Both expose the same HUD.* API.
local UI = require(script.Parent.UI)
return UI.TOUCH and require(script.Parent.HUDMobile) or require(script.Parent.HUDDesktop)
