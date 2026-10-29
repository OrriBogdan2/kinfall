extends Node
## The combat systems talk to each other through these signals instead of calling each other:
## the player's abilities, the kin's abilities, the kin AI, the bond meter and combos all listen here.

## Something landed a hit. `tags` says what kind (e.g. "primary", "utility", "kin", "stun").
signal hit_landed(attacker: Node, target: Node, amount: float, tags: Array)
## An ability was used. `slot` is "primary", "utility", "dodge", "kin_a", "kin_b" or "ultimate".
signal ability_used(caster: Node, ability_id: String, slot: String)
## A status (stun, root, slow, burn...) went onto a target.
signal status_applied(target: Node, status: String, by: Node, duration: float)
signal kin_thrown(kin: Node, owner: Node)
signal kin_recalled(kin: Node, owner: Node)
