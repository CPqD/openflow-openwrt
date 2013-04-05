module("trigger.openflow", package.seeall)
require("uci.trigger")

uci.trigger.add {
	{
		id = "openflow_restart",
		title = "Restart the openflow controller",
		package = "openflow",
		action = uci.trigger.service_restart("openflow")
	},
}

