import {
  allHoldMasks,
  applyHierarchy,
  describeHold,
  exactEVForHold,
  monteCarloEVForHold,
} from "./strategy.js";

self.addEventListener("message", (event) => {
  const { requestId, type, hand, remainder, coins, masks } = event.data;

  try {
    if (type === "estimate") {
      const rows = allHoldMasks().map((holdIndices) => ({
        holdIndices,
        minPayout: 0,
        maxPayout: 0,
        ev: monteCarloEVForHold({
          holdIndices,
          hand,
          remainder,
          coins,
          samples: 3000,
        }),
        title: describeHold(holdIndices, hand),
        isEstimate: true,
      }));

      self.postMessage({
        requestId,
        type: "estimateComplete",
        rows: applyHierarchy(rows, hand).slice(0, 4),
      });
      return;
    }

    if (type === "exact") {
      const rows = masks.map((holdIndices, index) => {
        const drawCount = 5 - holdIndices.length;
        const base = { holdIndices, title: describeHold(holdIndices, hand) };

        if (drawCount <= 3) {
          const exact = exactEVForHold({ holdIndices, hand, remainder, coins });
          self.postMessage({ requestId, type: "progress", completed: index + 1, total: masks.length });
          return { ...base, ...exact, isEstimate: false };
        }

        const ev = monteCarloEVForHold({
          holdIndices,
          hand,
          remainder,
          coins,
          samples: 30000,
        });
        self.postMessage({ requestId, type: "progress", completed: index + 1, total: masks.length });
        return { ...base, ev, minPayout: 0, maxPayout: 0, isEstimate: true };
      });

      self.postMessage({
        requestId,
        type: "exactComplete",
        rows: applyHierarchy(rows, hand),
      });
    }
  } catch (error) {
    self.postMessage({
      requestId,
      type: "error",
      message: error instanceof Error ? error.message : "EV calculation failed",
    });
  }
});
