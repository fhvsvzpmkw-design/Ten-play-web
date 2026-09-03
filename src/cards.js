export const SUITS = Object.freeze([
  Object.freeze({ key: "hearts", symbol: "♥", red: true }),
  Object.freeze({ key: "diamonds", symbol: "♦", red: true }),
  Object.freeze({ key: "clubs", symbol: "♣", red: false }),
  Object.freeze({ key: "spades", symbol: "♠", red: false }),
]);

export function createDeck() {
  return SUITS.flatMap((suit) =>
    Array.from({ length: 13 }, (_, index) => {
      const rank = index + 2;
      return Object.freeze({
        rank,
        suit: suit.key,
        symbol: suit.symbol,
        red: suit.red,
        id: `${rank}-${suit.key}`,
      });
    }),
  );
}

export function rankText(rank) {
  if (rank === 11) return "J";
  if (rank === 12) return "Q";
  if (rank === 13) return "K";
  if (rank === 14) return "A";
  return String(rank);
}

export function shortName(card) {
  return `${rankText(card.rank)}${card.symbol}`;
}

export function shuffleInPlace(cards, random = Math.random) {
  for (let i = cards.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
  return cards;
}

export function shuffled(cards, random = Math.random) {
  return shuffleInPlace([...cards], random);
}

export function drawFrom(deck, count) {
  const take = Math.max(0, Math.min(count, deck.length));
  return deck.splice(0, take);
}

export function cardsAreUnique(cards) {
  return new Set(cards.map((card) => card.id)).size === cards.length;
}
