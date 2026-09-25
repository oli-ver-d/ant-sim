class_name Corpse
extends Item
## A dead worker ("corpse") or larva ("brood_corpse") lying where it died,
## until a nestmate carries it to a midden (NestType "Corpses").

## Its colony and caste (-1 for brood), for drawing it.
var colony_id: int = -1
var caste_id: int = -1
