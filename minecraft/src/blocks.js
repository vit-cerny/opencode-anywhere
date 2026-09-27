// ponytail: id table only, no deps.
export const AIR = 0;
export const GRASS = 1;
export const DIRT = 2;
export const STONE = 3;
export const WOOD = 4;
export const LEAF = 5;
export const SAND = 6;
export const PLANK = 7;
export const BRICK = 8;
export const GLASS = 9;
export const WATER = 10;
export const BLOCKS = {
  [AIR]: "air",
  [GRASS]: "grass",
  [DIRT]: "dirt",
  [STONE]: "stone",
  [WOOD]: "wood",
  [LEAF]: "leaf",
  [SAND]: "sand",
  [PLANK]: "plank",
  [BRICK]: "brick",
  [GLASS]: "glass",
  [WATER]: "water"
};
export function isSolid(id) {
  return id !== AIR && id !== WATER;
}
export function isWater(id) {
  return id === WATER;
}
export function isValidId(id) {
  return Object.hasOwn(BLOCKS, id);
}
