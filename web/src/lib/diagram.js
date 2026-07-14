import diagram from "../data/diagram.json";

// each chip rides its wire into the junction, then out to its destination
export const events = diagram.chips.map((chip, i) => ({
  chip: i,
  dest: chip.dest,
  rule: chip.rule,
  color: diagram.destinations[chip.dest].hex,
  inPath: `in${i}`,
  dPath: `d${chip.dest}`,
}));
