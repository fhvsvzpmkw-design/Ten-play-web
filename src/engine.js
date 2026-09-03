import { createDeck, shuffled } from "./cards.js";

export const HandRank = Object.freeze({
  ROYAL_FLUSH: "Royal Flush",
  STRAIGHT_FLUSH: "Straight Flush",
  FOUR_OF_A_KIND: "Four of a Kind",
  FULL_HOUSE: "Full House",
  FLUSH: "Flush",
  STRAIGHT: "Straight",
  THREE_OF_A_KIND: "Three of a Kind",
  TWO_PAIR: "Two Pair",
  JACKS_OR_BETTER: "Jacks or Better",
  NOTHING: "Nothing",
});

export const BASE_PAYTABLE = Object.freeze({
  [HandRank.ROYAL_FLUSH]: Object.freeze([250, 500, 750, 1000, 4000]),
  [HandRank.STRAIGHT_FLUSH]: Object.freeze([50, 100, 150, 200, 250]),
  [HandRank.FOUR_OF_A_KIND]: Object.freeze([25, 50, 75, 100, 125]),
  [HandRank.FULL_HOUSE]: Object.freeze([9, 18, 27, 36, 45]),
  [HandRank.FLUSH]: Object.freeze([6, 12, 18, 24, 30]),
  [HandRank.STRAIGHT]: Object.freeze([4, 8, 12, 16, 20]),
  [HandRank.THREE_OF_A_KIND]: Object.freeze([3, 6, 9, 12, 15]),
  [HandRank.TWO_PAIR]: Object.freeze([2, 4, 6, 8, 10]),
  [HandRank.JACKS_OR_BETTER]: Object.freeze([1, 2, 3, 4, 5]),
  [HandRank.NOTHING]: Object.freeze([0, 0, 0, 0, 0]),
});

const HAND_RANK_VALUE = Object.freeze({
  [HandRank.ROYAL_FLUSH]: 10,
  [HandRank.STRAIGHT_FLUSH]: 9,
  [HandRank.FOUR_OF_A_KIND]: 8,
  [HandRank.FULL_HOUSE]: 7,
  [HandRank.FLUSH]: 6,
  [HandRank.STRAIGHT]: 5,
  [HandRank.THREE_OF_A_KIND]: 4,
  [HandRank.TWO_PAIR]: 3,
  [HandRank.JACKS_OR_BETTER]: 2,
  [HandRank.NOTHING]: 1,
});

export function countsBy(values) {
  const counts = new Map();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return counts;
}

export function isStraightRanks(ranks) {
  const unique = [...new Set(ranks)].sort((a, b) => a - b);
  if (unique.length !== 5) return false;
  if ([2, 3, 4, 5, 14].every((rank) => unique.includes(rank))) return true;
  return unique[4] - unique[0] === 4;
}

export function evaluateHand(cards) {
  if (cards.length !== 5) return HandRank.NOTHING;

  const ranks = cards.map((card) => card.rank);
  const rankCounts = countsBy(ranks);
  const frequencies = [...rankCounts.values()].sort((a, b) => b - a);
  const isFlush = new Set(cards.map((card) => card.suit)).size === 1;
  const isStraight = isStraightRanks(ranks);
  const royalRanks = [10, 11, 12, 13, 14];
  const isRoyal = royalRanks.every((rank) => rankCounts.has(rank));

  if (isFlush && isRoyal) return HandRank.ROYAL_FLUSH;
  if (isFlush && isStraight) return HandRank.STRAIGHT_FLUSH;
  if (frequencies[0] === 4) return HandRank.FOUR_OF_A_KIND;
  if (frequencies[0] === 3 && frequencies[1] === 2) return HandRank.FULL_HOUSE;
  if (isFlush) return HandRank.FLUSH;
  if (isStraight) return HandRank.STRAIGHT;
  if (frequencies[0] === 3) return HandRank.THREE_OF_A_KIND;
  if (frequencies[0] === 2 && frequencies[1] === 2) return HandRank.TWO_PAIR;

  for (const [rank, count] of rankCounts) {
    if (count === 2 && rank >= 11) return HandRank.JACKS_OR_BETTER;
  }
  return HandRank.NOTHING;
}

export function payoutFor(rank, coins) {
  const row = BASE_PAYTABLE[rank] ?? BASE_PAYTABLE[HandRank.NOTHING];
  const index = Math.max(0, Math.min(4, coins - 1));
  return row[index];
}

export function handRankValue(rank) {
  return HAND_RANK_VALUE[rank] ?? 0;
}

export function isPatHand(cards) {
  return [
    HandRank.STRAIGHT,
    HandRank.FLUSH,
    HandRank.FULL_HOUSE,
    HandRank.FOUR_OF_A_KIND,
    HandRank.STRAIGHT_FLUSH,
    HandRank.ROYAL_FLUSH,
  ].includes(evaluateHand(cards));
}

export function winningMask(cards, rank = evaluateHand(cards)) {
  const flags = Array(cards.length).fill(false);
  const rankCounts = countsBy(cards.map((card) => card.rank));

  if ([HandRank.ROYAL_FLUSH, HandRank.STRAIGHT_FLUSH, HandRank.FLUSH, HandRank.STRAIGHT].includes(rank)) {
    return flags.map(() => true);
  }

  const markRanks = (wantedRanks) => {
    cards.forEach((card, index) => {
      if (wantedRanks.includes(card.rank)) flags[index] = true;
    });
  };

  if (rank === HandRank.FOUR_OF_A_KIND) {
    markRanks([...rankCounts].filter(([, count]) => count === 4).map(([cardRank]) => cardRank));
  } else if (rank === HandRank.FULL_HOUSE) {
    markRanks([...rankCounts].filter(([, count]) => count >= 2).map(([cardRank]) => cardRank));
  } else if (rank === HandRank.THREE_OF_A_KIND) {
    markRanks([...rankCounts].filter(([, count]) => count === 3).map(([cardRank]) => cardRank));
  } else if (rank === HandRank.TWO_PAIR) {
    markRanks([...rankCounts].filter(([, count]) => count === 2).map(([cardRank]) => cardRank));
  } else if (rank === HandRank.JACKS_OR_BETTER) {
    markRanks([...rankCounts].filter(([cardRank, count]) => count === 2 && cardRank >= 11).map(([cardRank]) => cardRank));
  }

  return flags;
}

export function createRound({ coins = 5, handsCount = 10, random = Math.random } = {}) {
  const deck = shuffled(createDeck(), random);
  const originalHand = deck.splice(0, 5);
  return {
    coins,
    handsCount,
    originalHand,
    remainder: deck,
  };
}

export function drawTenHands({ originalHand, remainder, holdIndices, coins = 5, handsCount = 10, random = Math.random }) {
  const held = new Set(holdIndices);
  const replaceIndices = [0, 1, 2, 3, 4].filter((index) => !held.has(index));
  const outcomes = [];

  for (let play = 0; play < handsCount; play += 1) {
    const drawPool = shuffled(remainder, random);
    const cards = [...originalHand];
    replaceIndices.forEach((handIndex, drawIndex) => {
      cards[handIndex] = drawPool[drawIndex];
    });
    const rank = evaluateHand(cards);
    outcomes.push({
      cards,
      rank,
      payout: payoutFor(rank, coins),
      wins: winningMask(cards, rank),
      play: play + 1,
    });
  }

  return outcomes.sort((a, b) => {
    if (a.payout !== b.payout) return b.payout - a.payout;
    if (handRankValue(a.rank) !== handRankValue(b.rank)) return handRankValue(b.rank) - handRankValue(a.rank);
    return a.play - b.play;
  });
}
