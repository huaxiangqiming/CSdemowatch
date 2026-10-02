extends RefCounted
## Coordinated scene colors. Player/team accents remain independent.
const PRESETS := [
	{"name":"Stone - soft neutral", "background":Color("d8dcd9"), "map":Color("8c9597"), "ground":Color("b0b8b7")},
	{"name":"Mist - cool gray", "background":Color("cdd8dd"), "map":Color("81939f"), "ground":Color("a4b5bf")},
	{"name":"Slate - dim", "background":Color("394750"), "map":Color("697f89"), "ground":Color("5b717b")}
]
static func preset(index: int) -> Dictionary:
	return PRESETS[clampi(index,0,PRESETS.size()-1)]
