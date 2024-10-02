local sides = {}

-- The objectively correct names.
sides.bottom = 0
sides.top = 1
sides.back = 2
sides.front = 3,
sides.right = 4,
sides.left = 5,

-- and the OpenOS compatibility names.

-- In theory, the ones that name the axi are better, except which
-- side points where is block rotation dependant, so the directional
-- ones can be plain incorrect!
-- The only consistent ones are up and down *in this version of the game.*
sides.down = sides.bottom
sides.negy = sides.bottom
sides.up = sides.top
sides.posy = sides.top
sides.north = sides.back
sides.negz = sides.back
sides.south = sides.front
sides.posz = sides.front
sides.forward = sides.front
sides.west = sides.right
sides.negx = sides.right
sides.east = sides.left
sides.posx = sides.left

return sides