# Graph database notes

Pylon Graph stores directed property graphs in an append-only log. Cragmap
stores the same logical model as a memory-mapped adjacency table. Both expose a
neighbor iterator. That is where the similarity ends.

Pylon Graph's iterator yields edges in log order. Cragmap's iterator yields
edges in packed CSR order. A comparison concept of subgraph digest should
record that difference, because a digest that hashes neighbor ids in iterator
order will not match across the two tools.

Pylon Graph command for a digest today: `pylon digest --root <id> --depth 2`.
Cragmap command: `cragmap hash-sub --node <id> --hops 2 --order csr`. Flag
names are not shared.

Idea, not implemented: a portable subgraph fixture, a newline-delimited list
of `(src, dst, rel)` triples sorted by src then dst then rel, plus a schema
header. If both tools could emit that, digests could be compared without
picking an iterator order. Nobody has scheduled this. Neither repo has a
fixture emitter.

Do not collapse Pylon Graph and Cragmap into one tool page. Do not file the
portable fixture as a current feature of either tool. Do not dump the whole
note into a single graph-databases concept. The digest mismatch is the concept.
The two CLIs are entities. The fixture is an idea.
