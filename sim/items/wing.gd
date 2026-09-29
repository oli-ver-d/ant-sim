class_name Wing
extends Item
## A pair of wings (fore and hind) a queen shed after her nuptial flight
## (Founding), lying where they fell until they decay (`gone_at`).

## Simulated time it was shed, and when it is gone (views fade it out
## towards then).
var shed_at: float = 0.0
var gone_at: float = 0.0
## Length of the forewing, world units.
var length: float = 20.0
## Tint of the membrane (the shedding ant's caste colour, lightened).
var tint: Color = Color(0.85, 0.8, 0.7)
## Which side it came off (1 right, -1 left): the pair is drawn mirrored.
var side: float = 1.0
