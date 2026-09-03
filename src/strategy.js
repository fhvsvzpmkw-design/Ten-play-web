import { evaluateHand, isPatHand, payoutFor } from "./engine.js";
import { shortName, shuffled } from "./cards.js";

export const STRATEGY_CATEGORIES = Object.freeze([
  Object.freeze({ key: "madeHand", label: "Made Hand (Keep All)" }),
  Object.freeze({ key: "fourToRoyal", label: "4 Cards to Royal Flush" }),
  Object.freeze({ key: "fourToStraightFlush", label: "4 Cards to Straight Flush" }),
  Object.freeze({ key: "trips", label: "Three of a Kind (Keep 3)" }),
  Object.freeze({ key: "twoPairHold", label: "Two Pair (Keep Both)" }),
  Object.freeze({ key: "highPair", label: "High Pair (Jacks or Better)" }),
  Object.freeze({ key: "threeToRoyalStrong", label: "3 Cards to Royal (Strong)" }),
  Object.freeze({ key: "fourToFlush", label: "4 to Flush" }),
  Object.freeze({ key: "lowPair", label: "Low Pair (2–10)" }),
  Object.freeze({ key: "fourToOutsideStraight", label: "4 to Straight (Outside)" }),
  Object.freeze({ key: "threeToStraightFlushTypeA", label: "3 to Straight Flush (Tight/High)" }),
  Object.freeze({ key: "AKQJUnsuited", label: "AKQJ (3–4 High, Unsuited)" }),
  Object.freeze({ key: "twoSuitedHigh", label: "2 High Cards (Suited)" }),
  Object.freeze({ key: "threeToRoyalWeak", label: "3 Cards to Royal (Weak)" }),
  Object.freeze({ key: "threeToStraightFlushTypeB", label: "3 to Straight Flush (Loose)" }),
  Object.freeze({ key: "twoHighUnsuited", label: "2 High Cards (Unsuited)" }),
  Object.freeze({ key: "fourToInsideStraight", label: "4 to Straight (Inside)" }),
  Object.freeze({ key: "oneHighAce", label: "Single High (Ace)" }),
  Object.freeze({ key: "oneHighOther", label: "Single High (K/Q/J)" }),
  Object.freeze({ key: "trash", label: "Draw New Hand" }),
]);

const CATEGORY_BY_KEY = new Map(STRATEGY_CATEGORIES.map((category, order) => [category.key, { ...category, order }]));
const ROYAL_RANKS = new Set([10, 11, 12, 13, 14]);

function category(key) {
  return CATEGORY_BY_KEY.get(key);
}

function countByRank(cards) {
  const counts = new Map();
  for (const card of cards) counts.set(card.rank, (counts.get(card.rank) ?? 0) + 1);
  return counts;
}

function isHigh(rank) {
  return rank >= 11;
}

function groupsBySuit(cards) {
  const groups = new Map();
  for (const card of cards) {
    if (!groups.has(card.suit)) groups.set(card.suit, []);
    groups.get(card.suit).push(card);
  }
  return [...groups.values()];
}

function uniqueRanks(cards) {
  return [...new Set(cards.map((card) => card.rank))].sort((a, b) => a - b);
}

function span(ranks) {
  if (!ranks.length) return 0;
  return Math.max(...ranks) - Math.min(...ranks);
}

function hasTrips(cards) {
  return [...countByRank(cards).values()].some((count) => count === 3);
}

function hasPair(cards, minimumRank) {
  return [...countByRank(cards)].some(([rank, count]) => count >= 2 && rank >= minimumRank);
}

function hasLowPair(cards) {
  return [...countByRank(cards)].some(([rank, count]) => count >= 2 && rank < 11);
}

function isTwoPair(cards) {
  return [...countByRank(cards).values()].sort((a, b) => b - a).join(",") === "2,2";
}

function isFourToRoyal(cards) {
  return groupsBySuit(cards).some((group) => {
    if (group.length < 4) return false;
    const ranks = new Set(group.map((card) => card.rank));
    return ranks.size === 4 && [...ranks].every((rank) => ROYAL_RANKS.has(rank));
  });
}

function isThreeToRoyal(cards) {
  return groupsBySuit(cards).some((group) => {
    if (group.length < 3) return false;
    const ranks = new Set(group.map((card) => card.rank));
    return ranks.size === 3 && [...ranks].every((rank) => ROYAL_RANKS.has(rank));
  });
}

function isThreeToRoyalStrong(cards) {
  if (!isThreeToRoyal(cards)) return false;
  return groupsBySuit(cards).some((group) => {
    if (group.length < 3) return false;
    const ranks = new Set(group.map((card) => card.rank));
    return (
      [13, 12, 11].every((rank) => ranks.has(rank)) ||
      [12, 11, 10].every((rank) => ranks.has(rank)) ||
      [11, 10, 9].every((rank) => ranks.has(rank))
    );
  });
}

function isFourToStraightFlush(cards) {
  return groupsBySuit(cards).some((group) => {
    if (group.length !== 4) return false;
    const ranks = uniqueRanks(group);
    return ranks.length === 4 && span(ranks) <= 4;
  });
}

function isFourToFlush(cards) {
  if (cards.length !== 4) return false;
  return groupsBySuit(cards).some((group) => {
    if (group.length !== 4) return false;
    const ranks = uniqueRanks(group);
    return ranks.length < 4 || span(ranks) > 4;
  });
}

function isFourToOutsideStraight(cards) {
  const ranks = uniqueRanks(cards);
  if (ranks.length !== 4) return false;
  if ([14, 2, 3, 4].every((rank) => ranks.includes(rank))) return true;
  return span(ranks) === 3;
}

function isFourToInsideStraight(cards) {
  const ranks = uniqueRanks(cards);
  if (ranks.length !== 4) return false;
  if ([14, 2, 3, 4].every((rank) => ranks.includes(rank))) return false;
  return span(ranks) === 4;
}

function isThreeToStraightFlushTypeA(cards) {
  return groupsBySuit(cards).some((group) => {
    if (group.length !== 3) return false;
    const ranks = uniqueRanks(group);
    if (ranks.length < 3) return false;
    const rankSpan = span(ranks);
    return rankSpan <= 2 || (rankSpan === 3 && ranks.some((rank) => rank >= 10));
  });
}

function isThreeToStraightFlushTypeB(cards) {
  return groupsBySuit(cards).some((group) => {
    if (group.length !== 3) return false;
    const ranks = uniqueRanks(group);
    if (ranks.length < 3) return false;
    const rankSpan = span(ranks);
    return (
      (rankSpan === 3 && !ranks.some((rank) => rank >= 10)) ||
      (rankSpan === 4 && ranks.some((rank) => rank >= 10))
    );
  });
}

function twoHighSuited(cards) {
  const highs = cards.filter((card) => isHigh(card.rank));
  for (let first = 0; first < highs.length - 1; first += 1) {
    for (let second = first + 1; second < highs.length; second += 1) {
      if (highs[first].suit === highs[second].suit) return true;
    }
  }
  return false;
}

function twoHighUnsuited(cards) {
  return cards.filter((card) => isHigh(card.rank)).length === 2 && !twoHighSuited(cards);
}

function akqjUnsuitedBlock(cards) {
  const highRanks = cards.map((card) => card.rank).filter((rank) => [11, 12, 13, 14].includes(rank));
  if (highRanks.length < 3) return false;
  return ![...new Map(highRanks.map((rank) => [rank, highRanks.filter((item) => item === rank).length])).values()].some(
    (count) => count >= 2,
  );
}

function straightPenalty(held, hand) {
  const allRanks = hand.map((card) => card.rank);
  const ranks = uniqueRanks(held);
  if (ranks.length < 2) return 0;
  let penalty = 0;
  if (allRanks.includes(ranks[0] - 1)) penalty += 1;
  if (allRanks.includes(ranks[ranks.length - 1] + 1)) penalty += 1;
  return penalty;
}

function flushPenalty(held, hand) {
  if (!held.length) return 0;
  const heldSuit = held[0].suit;
  const handSuitCount = hand.filter((card) => card.suit === heldSuit).length;
  return Math.max(0, handSuitCount - held.length);
}

export function classifyHold(holdIndices, hand) {
  const held = holdIndices.map((index) => hand[index]);

  if (held.length === 5 && isPatHand(held)) return category("madeHand");
  if (isFourToRoyal(held)) return category("fourToRoyal");
  if (isFourToStraightFlush(held)) return category("fourToStraightFlush");
  if (held.length === 3 && hasTrips(held)) return category("trips");
  if (held.length === 4 && isTwoPair(held)) return category("twoPairHold");
  if (hasTrips(held)) return category("trips");
  if (hasPair(held, 11)) return category("highPair");
  if (isThreeToRoyalStrong(held)) return category("threeToRoyalStrong");
  if (isFourToFlush(held)) return category("fourToFlush");
  if (hasLowPair(held)) return category("lowPair");
  if (isFourToOutsideStraight(held) && straightPenalty(held, hand) <= 1) return category("fourToOutsideStraight");
  if (isThreeToStraightFlushTypeA(held)) return category("threeToStraightFlushTypeA");
  if (akqjUnsuitedBlock(held)) return category("AKQJUnsuited");
  if (twoHighSuited(held) && flushPenalty(held, hand) <= 1) return category("twoSuitedHigh");
  if (isThreeToRoyal(held) && !isThreeToRoyalStrong(held)) return category("threeToRoyalWeak");
  if (isThreeToStraightFlushTypeB(held)) return category("threeToStraightFlushTypeB");
  if (twoHighUnsuited(held)) return category("twoHighUnsuited");
  if (isFourToInsideStraight(held)) return category("fourToInsideStraight");
  if (held.length === 1 && held[0].rank === 14) return category("oneHighAce");
  if (held.length === 1 && isHigh(held[0].rank)) return category("oneHighOther");
  return category("trash");
}

export function allHoldMasks() {
  const masks = [];
  for (let mask = 0; mask < 32; mask += 1) {
    const indices = [];
    for (let index = 0; index < 5; index += 1) {
      if (mask & (1 << index)) indices.push(index);
    }
    masks.push(indices);
  }
  return masks;
}

export function describeHold(indices, hand) {
  return indices.length ? `Hold ${indices.map((index) => shortName(hand[index])).join(" ")}` : "Hold none";
}

export function monteCarloEVForHold({ holdIndices, hand, remainder, coins, samples, random = Math.random }) {
  const held = new Set(holdIndices);
  const replaceIndices = [0, 1, 2, 3, 4].filter((index) => !held.has(index));
  if (!replaceIndices.length) return payoutFor(evaluateHand(hand), coins);

  let total = 0;
  for (let sample = 0; sample < samples; sample += 1) {
    const pool = shuffled(remainder, random);
    const work = [...hand];
    replaceIndices.forEach((position, drawIndex) => {
      work[position] = pool[drawIndex];
    });
    total += payoutFor(evaluateHand(work), coins);
  }
  return total / samples;
}

export function forEachCombination(n, k, callback) {
  if (k < 0 || k > n) return;
  if (k === 0) {
    callback([]);
    return;
  }
  const combination = Array.from({ length: k }, (_, index) => index);
  while (true) {
    callback([...combination]);
    let cursor = k - 1;
    while (cursor >= 0 && combination[cursor] === cursor + n - k) cursor -= 1;
    if (cursor < 0) break;
    combination[cursor] += 1;
    for (let index = cursor + 1; index < k; index += 1) combination[index] = combination[index - 1] + 1;
  }
}

export function exactEVForHold({ holdIndices, hand, remainder, coins }) {
  const held = new Set(holdIndices);
  const replaceIndices = [0, 1, 2, 3, 4].filter((index) => !held.has(index));
  if (!replaceIndices.length) {
    const payout = payoutFor(evaluateHand(hand), coins);
    return { ev: payout, minPayout: payout, maxPayout: payout };
  }

  let total = 0;
  let count = 0;
  let minPayout = Number.POSITIVE_INFINITY;
  let maxPayout = Number.NEGATIVE_INFINITY;
  const work = [...hand];

  forEachCombination(remainder.length, replaceIndices.length, (combination) => {
    replaceIndices.forEach((position, drawIndex) => {
      work[position] = remainder[combination[drawIndex]];
    });
    const payout = payoutFor(evaluateHand(work), coins);
    total += payout;
    count += 1;
    minPayout = Math.min(minPayout, payout);
    maxPayout = Math.max(maxPayout, payout);
  });

  return {
    ev: total / count,
    minPayout: Number.isFinite(minPayout) ? minPayout : 0,
    maxPayout: Number.isFinite(maxPayout) ? maxPayout : 0,
  };
}

export function applyHierarchy(rows, hand) {
  const enriched = rows.map((row) => ({ ...row, category: classifyHold(row.holdIndices, hand) }));
  enriched.sort((first, second) => {
    if (first.category.order !== second.category.order) return first.category.order - second.category.order;
    if (Math.abs(first.ev - second.ev) > 1e-9) return second.ev - first.ev;
    if (first.holdIndices.length !== second.holdIndices.length) return first.holdIndices.length - second.holdIndices.length;
    return first.holdIndices.join("").localeCompare(second.holdIndices.join(""));
  });

  const topEV = enriched[0]?.ev ?? 0;
  return enriched.map((row) => ({
    ...row,
    strategyLabel: row.category.label,
    evPct: topEV > 0 ? Math.min(100, (row.ev / topEV) * 100) : 0,
  }));
}
