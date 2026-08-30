-- Copy this entry into the table returned by ox_inventory/data/items.lua.
-- Change "ox_fuel" in client.export if the resource folder has a different name.
return {
	['portable_ev_charger'] = {
		label = 'Portable EV Charger',
		weight = 12000,
		stack = false,
		close = true,
		consume = 0,
		description = 'A deployable 12 kWh emergency battery pack for electric vehicles.',
		client = {
			export = 'ox_fuel.portableEvCharger',
			-- Copy install/images/portable_ev_charger_compact.png into ox_inventory/web/images.
			image = 'portable_ev_charger_compact.png',
		},
	},
}
