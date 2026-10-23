fx_version 'cerulean'
game 'gta5'

name 'ox_fuel_assets'
author 'DrSnyder and ox_fuel Expanded contributors'
version '1.2.6'
description 'Original DRS Sentinel hardware, illuminated RON pump, and universal fuel nozzle'

files {
	'stream/sentinel_ev_station/drs_ev_station.ydr',
	'stream/sentinel_ev_station/drs_ev_station_typ.ytyp',
	'stream/sentinel_hardware/*.ydr',
	'stream/sentinel_hardware/*_typ.ytyp',
	'stream/ron_pump/*.ydr',
	'stream/ron_pump/*_typ.ytyp',
	'stream/fuel_nozzle/*.ydr',
	'stream/fuel_nozzle/*_typ.ytyp',
}

data_file 'DLC_ITYP_REQUEST' 'stream/sentinel_ev_station/drs_ev_station_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sentinel_hardware/drs_ev_connector_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sentinel_hardware/drs_ev_pack_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sentinel_hardware/drs_ev_pack_carry_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sentinel_hardware/drs_ev_cable_l_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sentinel_hardware/drs_ev_cable_r_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sentinel_hardware/drs_ev_pack_cable_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/ron_pump/drs_gas_pump_ron_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/ron_pump/drs_ron_hose_l_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/ron_pump/drs_ron_hose_r_typ.ytyp'

data_file 'DLC_ITYP_REQUEST' 'stream/fuel_nozzle/drs_fuel_nozzle_typ.ytyp'
