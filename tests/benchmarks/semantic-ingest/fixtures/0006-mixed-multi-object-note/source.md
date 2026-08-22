# Graph database notes

Pylon Graph stores directed property graphs in an append-only log. Cragmap
stores the same logical model as a memory-mapped adjacency table. Both expose a
neighbor iterator. That is where the similarity ends.

Pylon Graph's iterator yields edges in log order. Cragmap's iterator yields
edges in packed CSR order. A digest that hashes neighbor ids in iterator order
will not match across the two tools unless the order difference is handled.

Pylon Graph command for a digest today: `pylon digest --root <id> --depth 2`.
Cragmap command: `cragmap hash-sub --node <id> --hops 2 --order csr`. Flag
names are not shared.

Possible later work, not implemented: a portable subgraph fixture, a
newline-delimited list of `(src, dst, rel)` triples sorted by src then dst then
rel, plus a schema header. If both tools could emit that, digests could be
compared without picking an iterator order. Nobody has scheduled this. Neither
repo has a fixture emitter.

The note is for later comparison work. Keep the current behavior separate from
the unscheduled portable-fixture sketch when carrying the facts forward.
