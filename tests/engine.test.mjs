import test from "node:test";
import assert from "node:assert/strict";

import { cardsAreUnique, createDeck } from "../src/cards.js";
import {
  HandRank,
  drawTenHands,
  evaluateHand,
  payoutFor,
  winningMask,
} from "../src/engine.js";
import {
  allHoldMasks,
  applyHierarchy,
  classifyHold,
  exactEVForHold,
} from "../src/strategy.js";

const SUIT_SYMBOL = { hearts: "♥", diamonds: "♦", clubs: "♣", spades: "♠" };

function card(rank, suit) {
  return {
    rank,
    suit,
    symbol: SUIT_SYMBOL[suit],
    red: suit === "hearts" || suit === "diamonds",
    id: `${rank}-${suit}`,
  };
}

function seededRandom(seed = 123456789) {
  let state = seed >>> 0;
  return () => {
    state = (1664525 * state + 1013904223) >>> 0;
    return state / 2 ** 32;
  };
}

test("standard deck has 52 unique cards", () => {
  const deck = createDeck();
  assert.equal(deck.length, 52);
  assert.equal(cardsAreUnique(deck), true);
});

test("evaluates every Jacks or Better payout category", () => {
  const cases = [
    [HandRank.ROYAL_FLUSH, [card(10, "hearts"), card(11, "hearts"), card(12, "hearts"), card(13, "hearts"), card(14, "hearts")]],
    [HandRank.STRAIGHT_FLUSH, [card(5, "spades"), card(6, "spades"), card(7, "spades"), card(8, "spades"), card(9, "spades")]],
    [HandRank.FOUR_OF_A_KIND, [card(9, "spades"), card(9, "hearts"), card(9, "clubs"), card(9, "diamonds"), card(2, "spades")]],
    [HandRank.FULL_HOUSE, [card(8, "spades"), card(8, "hearts"), card(8, "clubs"), card(3, "diamonds"), card(3, "spades")]],
    [HandRank.FLUSH, [card(2, "clubs"), card(5, "clubs"), card(8, "clubs"), card(11, "clubs"), card(13, "clubs")]],
    [HandRank.STRAIGHT, [card(6, "clubs"), card(7, "spades"), card(8, "hearts"), card(9, "diamonds"), card(10, "clubs")]],
    [HandRank.STRAIGHT, [card(14, "clubs"), card(2, "spades"), card(3, "hearts"), card(4, "diamonds"), card(5, "clubs")]],
    [HandRank.THREE_OF_A_KIND, [card(4, "clubs"), card(4, "spades"), card(4, "hearts"), card(9, "diamonds"), card(12, "clubs")]],
    [HandRank.TWO_PAIR, [card(4, "clubs"), card(4, "spades"), card(12, "hearts"), card(12, "diamonds"), card(7, "clubs")]],
    [HandRank.JACKS_OR_BETTER, [card(13, "clubs"), card(13, "spades"), card(4, "hearts"), card(8, "diamonds"), card(10, "clubs")]],
    [HandRank.NOTHING, [card(2, "clubs"), card(4, "spades"), card(7, "hearts"), card(9, "diamonds"), card(12, "clubs")]],
  ];

  for (const [expected, hand] of cases) assert.equal(evaluateHand(hand), expected);
});

test("uses the 9/6 paytable and five-coin royal bonus", () => {
  assert.equal(payoutFor(HandRank.FULL_HOUSE, 1), 9);
  assert.equal(payoutFor(HandRank.FLUSH, 5), 30);
  assert.equal(payoutFor(HandRank.ROYAL_FLUSH, 4), 1000);
  assert.equal(payoutFor(HandRank.ROYAL_FLUSH, 5), 4000);
});

test("winning mask marks only the cards that form pair and trips wins", () => {
  const pair = [card(13, "clubs"), card(13, "spades"), card(4, "hearts"), card(8, "diamonds"), card(10, "clubs")];
  assert.deepEqual(winningMask(pair), [true, true, false, false, false]);

  const trips = [card(4, "clubs"), card(4, "spades"), card(4, "hearts"), card(9, "diamonds"), card(12, "clubs")];
  assert.deepEqual(winningMask(trips), [true, true, true, false, false]);
});

test("enumerates all 32 distinct hold masks", () => {
  const masks = allHoldMasks();
  assert.equal(masks.length, 32);
  assert.equal(new Set(masks.map((mask) => mask.join("-"))).size, 32);
  assert.equal(masks.some((mask) => mask.length === 0), true);
  assert.equal(masks.some((mask) => mask.length === 5), true);
});

test("retains the v1.9.1 trips and two-pair hierarchy tiers", () => {
  const tripsHand = [card(7, "clubs"), card(7, "spades"), card(7, "hearts"), card(12, "diamonds"), card(2, "clubs")];
  assert.equal(classifyHold([0, 1, 2], tripsHand).key, "trips");

  const twoPairHand = [card(5, "clubs"), card(5, "spades"), card(12, "hearts"), card(12, "diamonds"), card(2, "clubs")];
  assert.equal(classifyHold([0, 1, 2, 3], twoPairHand).key, "twoPairHold");
});

test("hierarchy recommendation and displayed first row use the same hold", () => {
  const hand = [card(12, "hearts"), card(12, "clubs"), card(3, "clubs"), card(8, "diamonds"), card(9, "spades")];
  const rows = [
    { holdIndices: [], ev: 0.36, isEstimate: true },
    { holdIndices: [0, 1], ev: 1.54, isEstimate: true },
  ];
  const sorted = applyHierarchy(rows, hand);
  assert.deepEqual(sorted[0].holdIndices, [0, 1]);
  assert.equal(sorted[0].strategyLabel, "High Pair (Jacks or Better)");
});

test("exact EV for a pat royal is its fixed payout", () => {
  const hand = [card(10, "hearts"), card(11, "hearts"), card(12, "hearts"), card(13, "hearts"), card(14, "hearts")];
  const remainder = createDeck().filter((deckCard) => !new Set(hand.map((held) => held.id)).has(deckCard.id));
  assert.deepEqual(exactEVForHold({ holdIndices: [0, 1, 2, 3, 4], hand, remainder, coins: 5 }), {
    ev: 4000,
    minPayout: 4000,
    maxPayout: 4000,
  });
});

test("ten-play draw keeps held cards and produces legal five-card hands", () => {
  const originalHand = [card(11, "hearts"), card(11, "clubs"), card(3, "clubs"), card(8, "diamonds"), card(9, "spades")];
  const heldIds = new Set(originalHand.slice(0, 2).map((held) => held.id));
  const remainder = createDeck().filter((deckCard) => !new Set(originalHand.map((dealt) => dealt.id)).has(deckCard.id));
  const outcomes = drawTenHands({
    originalHand,
    remainder,
    holdIndices: [0, 1],
    coins: 5,
    handsCount: 10,
    random: seededRandom(),
  });

  assert.equal(outcomes.length, 10);
  for (const outcome of outcomes) {
    assert.equal(outcome.cards.length, 5);
    assert.equal(cardsAreUnique(outcome.cards), true);
    assert.equal(heldIds.has(outcome.cards[0].id), true);
    assert.equal(heldIds.has(outcome.cards[1].id), true);
    assert.equal(outcome.payout >= 0, true);
  }
});
