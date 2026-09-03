import { rankText, shortName } from "./cards.js";
import { createRound, drawTenHands } from "./engine.js";

const STORAGE_KEY = "ten-play-web-session-v1";
const HANDS_COUNT = 10;

const elements = {
  credits: document.querySelector("#credits"),
  rtp: document.querySelector("#rtp"),
  totalIn: document.querySelector("#total-in"),
  totalOut: document.querySelector("#total-out"),
  mainHand: document.querySelector("#main-hand"),
  statusPrimary: document.querySelector("#status-primary"),
  statusSecondary: document.querySelector("#status-secondary"),
  totalBet: document.querySelector("#total-bet"),
  dealDraw: document.querySelector("#deal-draw"),
  suggestionsPanel: document.querySelector("#suggestions-panel"),
  suggestions: document.querySelector("#suggestions"),
  suggestionState: document.querySelector("#suggestion-state"),
  exactButton: document.querySelector("#exact-button"),
  resultsPanel: document.querySelector("#results-panel"),
  roundTotal: document.querySelector("#round-total"),
  resultGrid: document.querySelector("#result-grid"),
  resetSession: document.querySelector("#reset-session"),
  modeButtons: [...document.querySelectorAll(".mode-button")],
  coinButtons: [...document.querySelectorAll(".coin-button")],
};

function loadSession() {
  try {
    const stored = JSON.parse(localStorage.getItem(STORAGE_KEY));
    return {
      credits: Number.isInteger(stored?.credits) && stored.credits >= 0 ? stored.credits : 1000,
      totalIn: Number.isInteger(stored?.totalIn) && stored.totalIn >= 0 ? stored.totalIn : 0,
      totalOut: Number.isInteger(stored?.totalOut) && stored.totalOut >= 0 ? stored.totalOut : 0,
      coinBet: [1, 2, 3, 4, 5].includes(stored?.coinBet) ? stored.coinBet : 5,
      mode: stored?.mode === "casino" ? "casino" : "trainer",
    };
  } catch {
    return { credits: 1000, totalIn: 0, totalOut: 0, coinBet: 5, mode: "trainer" };
  }
}

const saved = loadSession();
const state = {
  phase: "idle",
  mode: saved.mode,
  credits: saved.credits,
  totalIn: saved.totalIn,
  totalOut: saved.totalOut,
  coinBet: saved.coinBet,
  hand: [],
  remainder: [],
  holds: Array(5).fill(false),
  winningCards: Array(5).fill(false),
  results: [],
  outcomes: [],
  lastPayoutTotal: 0,
  message: "Tap Deal",
  calculating: false,
  requestId: 0,
};

const evWorker = new Worker(new URL("./ev-worker.js", import.meta.url), { type: "module" });

function saveSession() {
  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({
      credits: state.credits,
      totalIn: state.totalIn,
      totalOut: state.totalOut,
      coinBet: state.coinBet,
      mode: state.mode,
    }),
  );
}

function modeName() {
  return state.mode === "casino" ? "Casino Mode" : "Trainer Mode";
}

function setHolds(indices) {
  const held = new Set(indices);
  state.holds = state.holds.map((_, index) => held.has(index));
}

function currentHoldIndices() {
  return state.holds.flatMap((held, index) => (held ? [index] : []));
}

function requestEstimates() {
  state.requestId += 1;
  state.calculating = true;
  state.results = [];
  state.message = "Estimating EV…";
  render();
  evWorker.postMessage({
    requestId: state.requestId,
    type: "estimate",
    hand: state.hand,
    remainder: state.remainder,
    coins: state.coinBet,
  });
}

function requestExact() {
  if (state.phase !== "dealt" || !state.results.length || state.calculating) return;
  state.requestId += 1;
  state.calculating = true;
  state.message = "Computing exact EV…";
  render();
  evWorker.postMessage({
    requestId: state.requestId,
    type: "exact",
    hand: state.hand,
    remainder: state.remainder,
    coins: state.coinBet,
    masks: state.results.map((row) => row.holdIndices),
  });
}

evWorker.addEventListener("message", (event) => {
  const payload = event.data;
  if (payload.requestId !== state.requestId || state.phase !== "dealt") return;

  if (payload.type === "progress") {
    state.message = `Computing exact EV… (${payload.completed}/${payload.total})`;
    elements.statusPrimary.textContent = state.message;
    elements.suggestionState.textContent = `${payload.completed}/${payload.total}`;
    return;
  }

  if (payload.type === "error") {
    state.calculating = false;
    state.message = "EV calculation unavailable";
    elements.suggestionState.textContent = "Unavailable";
    render();
    return;
  }

  if (payload.type === "estimateComplete" || payload.type === "exactComplete") {
    state.calculating = false;
    state.results = payload.rows;
    const top = state.results[0];
    if (top) {
      setHolds(top.holdIndices);
      state.message = `${top.title} · ${top.strategyLabel} · EV ${top.ev.toFixed(3)}${top.isEstimate ? " est." : ""}`;
    } else {
      state.message = "EV suggestions ready";
    }
    render();
  }
});

function deal() {
  const totalBet = state.coinBet * HANDS_COUNT;
  if (state.credits < totalBet) {
    state.message = `Not enough credits for 10 × ${state.coinBet}`;
    render();
    return;
  }

  state.credits -= totalBet;
  state.totalIn += totalBet;
  const round = createRound({ coins: state.coinBet, handsCount: HANDS_COUNT });
  state.hand = round.originalHand;
  state.remainder = round.remainder;
  state.holds = Array(5).fill(false);
  state.winningCards = Array(5).fill(false);
  state.results = [];
  state.outcomes = [];
  state.lastPayoutTotal = 0;
  state.phase = "dealt";
  saveSession();
  requestEstimates();
}

function draw() {
  if (state.phase !== "dealt" || state.calculating) return;
  state.requestId += 1;
  state.outcomes = drawTenHands({
    originalHand: state.hand,
    remainder: state.remainder,
    holdIndices: currentHoldIndices(),
    coins: state.coinBet,
    handsCount: HANDS_COUNT,
  });

  const total = state.outcomes.reduce((sum, outcome) => sum + outcome.payout, 0);
  state.credits += total;
  state.totalOut += total;
  state.lastPayoutTotal = total;
  state.phase = "roundComplete";
  state.results = [];
  state.calculating = false;

  const top = state.outcomes[0];
  if (top) {
    state.hand = top.cards;
    state.winningCards = top.wins;
  }
  state.message = "Round complete";
  saveSession();
  render();
}

function makeCard(card, index) {
  const cardElement = document.createElement("button");
  cardElement.type = "button";
  cardElement.className = `card${card.red ? " red" : ""}${state.holds[index] ? " is-held" : ""}${state.winningCards[index] ? " is-winning" : ""}`;
  cardElement.setAttribute("aria-label", `${shortName(card)}${state.holds[index] ? ", held" : ""}`);
  cardElement.disabled = state.phase !== "dealt";
  if (state.phase === "dealt") cardElement.setAttribute("aria-pressed", String(state.holds[index]));

  const topCorner = document.createElement("span");
  topCorner.className = "card-corner";
  topCorner.innerHTML = `<span>${rankText(card.rank)}</span><span>${card.symbol}</span>`;
  const suit = document.createElement("span");
  suit.className = "card-suit";
  suit.textContent = card.symbol;
  const bottomCorner = topCorner.cloneNode(true);
  bottomCorner.classList.add("bottom");
  cardElement.append(topCorner, suit, bottomCorner);

  if (state.holds[index] && state.phase === "dealt") {
    const label = document.createElement("span");
    label.className = "hold-label";
    label.textContent = "HELD";
    cardElement.append(label);
  }

  cardElement.addEventListener("click", () => {
    if (state.phase !== "dealt") return;
    state.holds[index] = !state.holds[index];
    renderMainHand();
  });
  return cardElement;
}

function renderMainHand() {
  elements.mainHand.replaceChildren();
  if (state.phase === "idle") {
    for (let index = 0; index < 5; index += 1) {
      const back = document.createElement("div");
      back.className = "card-back";
      back.setAttribute("aria-label", "Face-down card");
      elements.mainHand.append(back);
    }
    return;
  }
  state.hand.forEach((card, index) => elements.mainHand.append(makeCard(card, index)));
}

function makeMiniHold(hand, holdIndices) {
  const strip = document.createElement("span");
  strip.className = "mini-hold";
  const held = new Set(holdIndices);
  hand.forEach((card, index) => {
    const mini = document.createElement("span");
    if (held.has(index)) {
      mini.className = `mini-card${card.red ? " red" : ""}`;
      mini.textContent = `${rankText(card.rank)}${card.symbol}`;
    } else {
      mini.className = "mini-back";
      mini.textContent = "10";
    }
    strip.append(mini);
  });
  return strip;
}

function renderSuggestions() {
  const visible = state.phase === "dealt";
  elements.suggestionsPanel.hidden = !visible;
  if (!visible) return;

  elements.suggestionState.textContent = state.calculating ? "Calculating" : state.results.some((row) => row.isEstimate) ? "Estimate" : "Exact";
  elements.suggestions.replaceChildren();

  if (!state.results.length) {
    const loading = document.createElement("p");
    loading.className = "meter-label";
    loading.textContent = "Checking all 32 hold combinations…";
    elements.suggestions.append(loading);
  }

  state.results.slice(0, 4).forEach((row, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `suggestion${index === 0 ? " is-best" : ""}`;
    button.append(makeMiniHold(state.hand, row.holdIndices));

    const copy = document.createElement("span");
    copy.className = "suggestion-copy";
    const label = document.createElement("strong");
    if (index === 0) {
      const badge = document.createElement("span");
      badge.className = "best-badge";
      badge.textContent = "BEST";
      label.append(badge);
    }
    label.append(document.createTextNode(row.strategyLabel));
    const title = document.createElement("small");
    title.textContent = row.title;
    copy.append(label, title);

    const ev = document.createElement("span");
    ev.className = "ev-block";
    const evValue = document.createElement("strong");
    evValue.textContent = `EV ${row.ev.toFixed(3)}`;
    const exactRange = document.createElement("small");
    exactRange.textContent = row.isEstimate ? "estimated" : `${row.minPayout}–${row.maxPayout} credits`;
    const track = document.createElement("span");
    track.className = "heat-track";
    const fill = document.createElement("span");
    fill.className = `heat-fill${row.evPct >= 95 ? " best" : row.evPct >= 85 ? " good" : ""}`;
    fill.style.width = `${Math.max(0, Math.min(100, row.evPct))}%`;
    track.append(fill);
    ev.append(evValue, exactRange, track);

    button.append(copy, ev);
    button.addEventListener("click", () => {
      setHolds(row.holdIndices);
      state.message = `${row.title} · ${row.strategyLabel} · EV ${row.ev.toFixed(3)}${row.isEstimate ? " est." : ""}`;
      render();
    });
    elements.suggestions.append(button);
  });

  const allExact = state.results.length > 0 && state.results.every((row) => !row.isEstimate);
  elements.exactButton.disabled = state.calculating || !state.results.length || allExact;
  elements.exactButton.textContent = allExact ? "Exact EV shown" : state.calculating ? "Calculating…" : "Show exact EV for these holds";
}

function makeResultHand(outcome, index) {
  const tile = document.createElement("article");
  tile.className = "result-hand";
  tile.setAttribute("aria-label", `Hand ${index + 1}: ${outcome.rank}, ${outcome.payout} credits`);

  const cards = document.createElement("div");
  cards.className = "result-cards";
  outcome.cards.forEach((card, cardIndex) => {
    const item = document.createElement("span");
    item.className = `result-card${card.red ? " red" : ""}${outcome.wins[cardIndex] ? " is-winning" : ""}`;
    item.textContent = `${rankText(card.rank)}${card.symbol}`;
    cards.append(item);
  });

  const caption = document.createElement("div");
  caption.className = "result-caption";
  const rank = document.createElement("span");
  rank.textContent = outcome.rank;
  const payout = document.createElement("strong");
  payout.textContent = `${outcome.payout} cr`;
  caption.append(rank, payout);
  tile.append(cards, caption);
  return tile;
}

function renderResults() {
  const visible = state.phase === "roundComplete" && state.outcomes.length === HANDS_COUNT;
  elements.resultsPanel.hidden = !visible;
  if (!visible) return;
  elements.roundTotal.textContent = `${state.lastPayoutTotal} credits`;
  elements.resultGrid.replaceChildren(...state.outcomes.map(makeResultHand));
}

function renderStatus() {
  if (state.phase === "roundComplete") {
    const top = state.outcomes[0];
    elements.statusPrimary.textContent = `10-play payout: ${state.lastPayoutTotal} credits`;
    elements.statusSecondary.textContent = top ? `Main Hand: ${top.rank} (${top.payout})` : "Main Hand: —";
  } else {
    elements.statusPrimary.textContent = state.message;
    elements.statusSecondary.textContent = modeName();
  }
}

function renderControls() {
  elements.modeButtons.forEach((button) => button.classList.toggle("is-active", button.dataset.mode === state.mode));
  elements.coinButtons.forEach((button) => {
    button.classList.toggle("is-active", Number(button.dataset.coins) === state.coinBet);
    button.disabled = state.phase === "dealt";
  });
  elements.totalBet.textContent = `${state.coinBet} × 10 = ${state.coinBet * HANDS_COUNT} credits`;

  if (state.phase === "dealt") {
    elements.dealDraw.textContent = `Draw (10-Play) — ${state.mode === "casino" ? "Casino" : "Trainer"}`;
    elements.dealDraw.disabled = state.calculating;
  } else {
    elements.dealDraw.textContent = `Deal — ${state.mode === "casino" ? "Casino" : "Trainer"}`;
    elements.dealDraw.disabled = false;
  }
}

function renderMeters() {
  const rtp = state.totalIn === 0 ? 0 : (state.totalOut * 100) / state.totalIn;
  elements.credits.textContent = state.credits.toLocaleString();
  elements.rtp.textContent = `${rtp.toFixed(1)}%`;
  elements.totalIn.textContent = state.totalIn.toLocaleString();
  elements.totalOut.textContent = state.totalOut.toLocaleString();
}

function render() {
  renderMeters();
  renderMainHand();
  renderStatus();
  renderControls();
  renderSuggestions();
  renderResults();
}

elements.modeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    state.mode = button.dataset.mode;
    saveSession();
    render();
  });
});

elements.coinButtons.forEach((button) => {
  button.addEventListener("click", () => {
    if (state.phase === "dealt") return;
    state.coinBet = Number(button.dataset.coins);
    saveSession();
    render();
  });
});

elements.dealDraw.addEventListener("click", () => {
  if (state.phase === "dealt") draw();
  else deal();
});

elements.exactButton.addEventListener("click", requestExact);

elements.resetSession.addEventListener("click", () => {
  const confirmed = window.confirm("Reset credits and RTP totals to the starting session?");
  if (!confirmed) return;
  state.requestId += 1;
  state.phase = "idle";
  state.credits = 1000;
  state.totalIn = 0;
  state.totalOut = 0;
  state.hand = [];
  state.remainder = [];
  state.holds = Array(5).fill(false);
  state.winningCards = Array(5).fill(false);
  state.results = [];
  state.outcomes = [];
  state.lastPayoutTotal = 0;
  state.calculating = false;
  state.message = "Tap Deal";
  saveSession();
  render();
});

render();
