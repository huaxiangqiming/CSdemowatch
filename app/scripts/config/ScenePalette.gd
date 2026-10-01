extends RefCounted
## Coordinated scene colors. Player/team accents remain independent.
const PRESETS := [
	{"name":"Stone - soft neutral", "background":Color("c4c7c2"), "map":Color("929b93"), "ground":Color("a4ada5")},
	{"name":"Mist - cool gray", "background":Color("b7c4cb"), "map":Color("8298a3"), "ground":Color("94a8b1")},
	{"name":"Slate - dim", "background":Color("394750"), "map":Color("697f89"), "ground":Color("5b717b")}
]
static func preset(index: int) -> Dictionary:
	return PRESETS[clampi(index,0,PRESETS.size()-1)]
