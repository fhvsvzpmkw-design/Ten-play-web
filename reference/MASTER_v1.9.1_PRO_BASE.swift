import SwiftUI

// ======================================================
// MASTER_v1.9.1_PRO_BASE
// Video Poker Trainer — 9/6 Jacks or Better
//
// Version 1.9.1 Update:
// - Added distinct Trips tier: "Three of a Kind (Keep 3)" ranked above pairs
// - Added distinct Two-Pair tier: "Two Pair (Keep Both)" ranked above High Pair
// - Removed [Trainer]/[Casino] tag from message line (status line keeps mode)
// - No change to flush logic (verification deferred)
// - EV core unchanged (MC-first, Exact-on-demand)
// ======================================================

// MARK: - Models

enum Suit: String, CaseIterable {
    case hearts = "♥️"
    case diamonds = "♦️"
    case clubs = "♣️"
    case spades = "♠️"
}

struct Card: Identifiable, Hashable {
    let rank: Int
    let suit: Suit
    var id: String { "\(rank)-\(suit.rawValue)" }
    var shortName: String {
        switch rank {
        case 11: return "J\(suit.rawValue)"
        case 12: return "Q\(suit.rawValue)"
        case 13: return "K\(suit.rawValue)"
        case 14: return "A\(suit.rawValue)"
        default: return "\(rank)\(suit.rawValue)"
        }
    }
}

struct Deck {
    var cards: [Card] = Suit.allCases.flatMap { s in (2...14).map { Card(rank: $0, suit: s) } }
    mutating func shuffle() { cards.shuffle() }
    mutating func draw(_ n: Int) -> [Card] {
        let k = min(n, cards.count)
        let taken = Array(cards.prefix(k))
        cards.removeFirst(k)
        return taken
    }
}

enum HandRank: String {
    case royalFlush = "Royal Flush"
    case straightFlush = "Straight Flush"
    case fourOfAKind = "Four of a Kind"
    case fullHouse = "Full House"
    case flush = "Flush"
    case straight = "Straight"
    case threeOfAKind = "Three of a Kind"
    case twoPair = "Two Pair"
    case jacksOrBetter = "Jacks or Better"
    case nothing = "Nothing"
}

let basePaytable: [HandRank: [Int]] = [
    .royalFlush:      [250, 500,  750, 1000, 4000],
    .straightFlush:   [ 50, 100,  150,  200,  250],
    .fourOfAKind:     [ 25,  50,   75,  100,  125],
    .fullHouse:       [  9,  18,   27,   36,   45],
    .flush:           [  6,  12,   18,   24,   30],
    .straight:        [  4,   8,   12,   16,   20],
    .threeOfAKind:    [  3,   6,    9,   12,   15],
    .twoPair:         [  2,   4,    6,    8,   10],
    .jacksOrBetter:   [  1,   2,    3,    4,    5],
    .nothing:         [  0,   0,    0,    0,    0]
]

// MARK: - Hand Evaluation

struct HandEvaluator {
    static func evaluate(_ cards: [Card]) -> HandRank {
        guard cards.count == 5 else { return .nothing }
        let ranks = cards.map { $0.rank }
        let rankCounts = Dictionary(grouping: cards, by: { $0.rank }).mapValues { $0.count }
        let freq = rankCounts.values.sorted(by: >)
        let suitsCount = Dictionary(grouping: cards, by: { $0.suit }).mapValues { $0.count }
        let isFlush = suitsCount.values.contains(5)
        let isStraight = checkStraight(ranks)
        
        if isFlush && Set(ranks) == Set([10, 11, 12, 13, 14]) { return .royalFlush }
        if isFlush && isStraight { return .straightFlush }
        if freq.first == 4 { return .fourOfAKind }
        if freq == [3, 2] { return .fullHouse }
        if isFlush { return .flush }
        if isStraight { return .straight }
        if freq.first == 3 { return .threeOfAKind }
        if freq == [2, 2, 1] { return .twoPair }
        if freq == [2, 1, 1, 1],
           let pr = rankCounts.first(where: { $0.value == 2 })?.key,
           pr >= 11 { return .jacksOrBetter }
        return .nothing
    }
    
    static func checkStraight(_ r: [Int]) -> Bool {
        var u: [Int] = []
        for x in r.sorted() { if u.last != x { u.append(x) } }
        if Set(u) == Set([2, 3, 4, 5, 14]) { return true } // Wheel A-5
        guard u.count >= 5 else { return false }
        for i in 0...(u.count - 5) {
            if u[i + 4] - u[i] == 4 { return true }
        }
        return false
    }
    
    static func isPat(_ cards: [Card]) -> Bool {
        switch evaluate(cards) {
        case .straight, .flush, .fullHouse, .fourOfAKind, .straightFlush, .royalFlush:
            return true
        default:
            return false
        }
    }
}

// MARK: - EV Helpers

@inline(__always)
func payoutFor(rank: HandRank, coins: Int) -> Int {
    let arr = basePaytable[rank] ?? [0, 0, 0, 0, 0]
    let idx = max(0, min(4, coins - 1))
    return arr[idx]
}

enum EVEngine {
    static func allHoldMasks() -> [[Int]] {
        var masks: [[Int]] = []
        func dfs(_ i: Int, _ cur: [Int]) {
            if i == 5 { masks.append(cur.sorted()); return }
            dfs(i + 1, cur)
            var next = cur; next.append(i); dfs(i + 1, next)
        }
        dfs(0, [])
        return masks
    }
    
    static func describeHold(indices: [Int], hand: [Card]) -> String {
        indices.isEmpty ? "Hold none" : "Hold " + indices.map { hand[$0].shortName }.joined(separator: " ")
    }
    
    static func forEachCombination(n: Int, k: Int, _ body: (_ idxs: [Int]) -> Void) {
        if k < 0 || k > n { return }
        if k == 0 { body([]); return }
        var c = Array(0..<k)
        while true {
            body(c)
            var i = k - 1
            while i >= 0 && c[i] == i + n - k { i -= 1 }
            if i < 0 { break }
            c[i] += 1
            if i < k - 1 {
                for j in (i + 1)..<k { c[j] = c[j - 1] + 1 }
            }
        }
    }
    
    static func exactEVForHold(
        holdIdxs: [Int], hand: [Card], remainder: [Card], coins: Int
    ) -> (ev: Double, minPay: Int, maxPay: Int) {
        let toReplace = Set(0..<5).subtracting(holdIdxs).sorted()
        let drawCount = toReplace.count
        if drawCount == 0 {
            let pay = payoutFor(rank: HandEvaluator.evaluate(hand), coins: coins)
            return (Double(pay), pay, pay)
        }
        var totalPay = 0, count = 0
        var minPay = Int.max, maxPay = Int.min
        var work = hand
        forEachCombination(n: remainder.count, k: drawCount) { combo in
            for (j, pos) in toReplace.enumerated() { work[pos] = remainder[combo[j]] }
            let pay = payoutFor(rank: HandEvaluator.evaluate(work), coins: coins)
            totalPay &+= pay; count &+= 1
            if pay < minPay { minPay = pay }
            if pay > maxPay { maxPay = pay }
        }
        return (Double(totalPay) / Double(count),
                minPay == Int.max ? 0 : minPay,
                maxPay == Int.min ? 0 : maxPay)
    }
    
    static func monteCarloEVForHold<T: RandomNumberGenerator>(
        holdIdxs: [Int], hand: [Card], remainder: [Card], coins: Int,
        samples: Int, rng: inout T
    ) -> Double {
        let toReplace = Set(0..<5).subtracting(holdIdxs).sorted()
        let drawCount = toReplace.count
        if drawCount == 0 {
            let pay = payoutFor(rank: HandEvaluator.evaluate(hand), coins: coins)
            return Double(pay)
        }
        var sum = 0.0
        var work = hand
        for _ in 0..<samples {
            var pool = remainder
            pool.shuffle(using: &rng)
            for j in 0..<drawCount { work[toReplace[j]] = pool[j] }
            sum += Double(payoutFor(rank: HandEvaluator.evaluate(work), coins: coins))
        }
        return sum / Double(samples)
    }
}

// MARK: - Strategy (Bob Dancer 9/6 JoB) — Pro hierarchy + penalties

enum StrategyCategory: Int {
    case madeHand = 0                     // Pat ≥ Straight
    
    case fourToRoyal                      // 4 to Royal Flush
    case fourToStraightFlush              // 4 to Straight Flush
    
    case trips                            // Three of a Kind (Keep 3)
    case twoPairHold                      // Two Pair (Keep Both)
    case highPair                         // JJ-AA
    
    case threeToRoyalStrong               // 3 to Royal (KQJ/QJT/JT9 suited)
    case fourToFlush                      // 4 to Flush (not SF)
    case lowPair                          // 22–TT
    
    case fourToOutsideStraight            // 4 to Outside Straight (e.g., 6789, TJQK, A234)
    case threeToStraightFlushTypeA        // 3 to SF: 0-gap, or 1-gap with ≥1 high (T+)
    case AKQJUnsuited                     // A,K,Q,J unsuited (any 3 or 4 highs no pair)
    
    case twoSuitedHigh                    // Exactly two suited highs (AK, AQ, AJ, KQ, KJ, QJ)
    case threeToRoyalWeak                 // 3 to Royal weak (≤1 high)
    case threeToStraightFlushTypeB        // 3 to SF: 1-gap no-high or 2-gap with ≥1 high
    
    case twoHighUnsuited                  // Two highs unsuited
    case fourToInsideStraight             // 4 to Inside Straight
    case oneHighAce                       // Single Ace
    case oneHighOther                     // Single K/Q/J
    
    case trash                            // Draw 5
}

struct Strategy {
    
    // MARK: Labels
    static func label(_ c: StrategyCategory) -> String {
        switch c {
        case .madeHand: return "Made Hand (Keep All)"
        case .fourToRoyal: return "4 Cards to Royal Flush"
        case .fourToStraightFlush: return "4 Cards to Straight Flush"
        case .trips: return "Three of a Kind (Keep 3)"
        case .twoPairHold: return "Two Pair (Keep Both)"
        case .highPair: return "High Pair (Jacks or Better)"
        case .threeToRoyalStrong: return "3 Cards to Royal (Strong)"
        case .fourToFlush: return "4 to Flush"
        case .lowPair: return "Low Pair (2–10)"
        case .fourToOutsideStraight: return "4 to Straight (Outside)"
        case .threeToStraightFlushTypeA: return "3 to Straight Flush (Tight/High)"
        case .AKQJUnsuited: return "AKQJ (3–4 High, Unsuited)"
        case .twoSuitedHigh: return "2 High Cards (Suited)"
        case .threeToRoyalWeak: return "3 Cards to Royal (Weak)"
        case .threeToStraightFlushTypeB: return "3 to Straight Flush (Loose)"
        case .twoHighUnsuited: return "2 High Cards (Unsuited)"
        case .fourToInsideStraight: return "4 to Straight (Inside)"
        case .oneHighAce: return "Single High (Ace)"
        case .oneHighOther: return "Single High (K/Q/J)"
        case .trash: return "Draw New Hand"
        }
    }
    
    // MARK: Helpers
    static func isHigh(_ r: Int) -> Bool { r >= 11 }                 // J Q K A
    static func highsCount(_ rs: [Int]) -> Int { rs.filter { isHigh($0) }.count }
    
    static func countByRank(_ ranks: [Int]) -> [Int: Int] {
        Dictionary(grouping: ranks, by: { $0 }).mapValues { $0.count }
    }
    
    static func hasPair(_ ranks: [Int], minRank: Int) -> Bool {
        countByRank(ranks).contains { $0.value >= 2 && $0.key >= minRank }
    }
    static func hasLowPair(_ ranks: [Int]) -> Bool {
        countByRank(ranks).contains { $0.value >= 2 && $0.key < 11 }
    }
    static func hasTrips(_ ranks: [Int]) -> Bool {
        countByRank(ranks).contains { $0.value == 3 }
    }
    static func isTwoPairRanks(_ ranks: [Int]) -> Bool {
        let c = countByRank(ranks).values.sorted(by: >)
        return c == [2,2]
    }
    
    static func isPatHand(_ cards: [Card]) -> Bool { HandEvaluator.isPat(cards) }
    
    static func groupedBySuit(_ cards: [Card]) -> [[Card]] {
        Dictionary(grouping: cards, by: { $0.suit }).values.map(Array.init)
    }
    
    static func uniqRanks(_ cards: [Card]) -> [Int] {
        Array(Set(cards.map { $0.rank })).sorted()
    }
    
    static func span(_ ranks: [Int]) -> Int {
        guard let mi = ranks.min(), let ma = ranks.max() else { return 0 }
        return ma - mi
    }
    
    // MARK: Pattern detectors
    
    // 4 to Royal
    static func isFourToRoyal(_ cards: [Card]) -> Bool {
        let R: Set<Int> = [10,11,12,13,14]
        for g in groupedBySuit(cards) where g.count >= 4 {
            let rset = Set(g.map(\.rank))
            if rset.isSubset(of: R) && rset.count == 4 { return true }
        }
        return false
    }
    
    // 3 to Royal
    static func isThreeToRoyal(_ cards: [Card]) -> Bool {
        let R: Set<Int> = [10,11,12,13,14]
        for g in groupedBySuit(cards) where g.count >= 3 {
            let rset = Set(g.map(\.rank))
            if rset.isSubset(of: R) && rset.count == 3 { return true }
        }
        return false
    }
    static func isThreeToRoyalStrong(_ cards: [Card]) -> Bool {
        guard isThreeToRoyal(cards) else { return false }
        for g in groupedBySuit(cards) where g.count >= 3 {
            let s = Set(g.map(\.rank))
            if s.isSuperset(of: [13,12,11]) { return true }      // KQJ
            if s.isSuperset(of: [12,11,10]) { return true }      // QJT
            if s.isSuperset(of: [11,10,9])  { return true }      // JT9
        }
        return false
    }
    static func isThreeToRoyalWeak(_ cards: [Card]) -> Bool {
        isThreeToRoyal(cards) && !isThreeToRoyalStrong(cards)
    }
    
    // 4 to Straight Flush
    static func isFourToStraightFlush(_ cards: [Card]) -> Bool {
        for g in groupedBySuit(cards) where g.count == 4 {
            let u = uniqRanks(g)
            if u.count < 4 { continue }
            if u.last! - u.first! <= 4 { return true }
        }
        return false
    }
    
    // 4 to Flush (not SF)
    // Must be exactly 4 cards, not 5 — prevents false positives on full suited hands
    static func isFourToFlush(_ cards: [Card]) -> Bool {
        // Flush draw logic only applies to exactly 4 held cards
        if cards.count != 4 { return false }
        
        for g in groupedBySuit(cards) where g.count == 4 {
            let u = uniqRanks(g)
            // Duplicate ranks still count (e.g. 2♣ 2♣ 5♣ 9♣)
            if u.count < 4 { return true }
            // Exclude Straight Flush possibility
            if !(u.last! - u.first! <= 4) { return true }
        }
        return false
    }
    
    // 4 to Outside Straight
    static func isFourToOutsideStraight(_ cards: [Card]) -> Bool {
        let u = uniqRanks(cards)
        guard u.count == 4 else { return false }
        if Set(u) == Set([14,2,3,4]) { return true } // A234
        return u.last! - u.first! == 3
    }
    
    // 4 to Inside Straight
    static func isFourToInsideStraight(_ cards: [Card]) -> Bool {
        let u = uniqRanks(cards)
        guard u.count == 4 else { return false }
        if Set(u) == Set([14,2,3,4]) { return false }
        return u.last! - u.first! == 4
    }
    
    // 3 to Straight Flush strength splits
    // Type A: span ≤ 2  OR span == 3 with ≥1 high (T or higher)
    static func isThreeToStraightFlushTypeA(_ cards: [Card]) -> Bool {
        for g in groupedBySuit(cards) where g.count == 3 {
            let u = uniqRanks(g)
            if u.count < 3 { continue }
            let s = span(u)
            if s <= 2 { return true }
            if s == 3 && u.contains(where: { $0 >= 10 }) { return true }
        }
        return false
    }
    // Type B: span == 3 with no high, or span == 4 with ≥1 high
    static func isThreeToStraightFlushTypeB(_ cards: [Card]) -> Bool {
        for g in groupedBySuit(cards) where g.count == 3 {
            let u = uniqRanks(g)
            if u.count < 3 { continue }
            let s = span(u)
            if s == 3 && !u.contains(where: { $0 >= 10 }) { return true }
            if s == 4 && u.contains(where: { $0 >= 10 }) { return true }
        }
        return false
    }
    
    // High-card groups
    static func twoHighSuited(_ cards: [Card]) -> Bool {
        let hs = cards.filter { isHigh($0.rank) }
        guard hs.count >= 2 else { return false }
        for i in 0..<(hs.count-1) {
            for j in (i+1)..<hs.count {
                if hs[i].suit == hs[j].suit { return true }
            }
        }
        return false
    }
    
    static func twoHighUnsuited(_ cards: [Card]) -> Bool {
        highsCount(cards.map(\.rank)) == 2 && !twoHighSuited(cards)
    }
    
    static func AKQJUnsuitedBlock(_ cards: [Card]) -> Bool {
        // any 3 or 4 of A,K,Q,J with no pair, unsuited as a set
        let r = cards.map(\.rank)
        let highs = r.filter { [11,12,13,14].contains($0) }
        if highs.count < 3 { return false }
        if countByRank(highs).values.contains(where: { $0 >= 2 }) { return false } // avoid pair
        return true
    }
    
    // Penalties: crude but effective
    static func straightPenalty(_ held: [Card], in hand: [Card]) -> Int {
        let allRanks = hand.map(\.rank)
        let u = Array(Set(held.map(\.rank))).sorted()
        if u.count < 2 { return 0 }
        let lo = u.first!, hi = u.last!
        var pen = 0
        if allRanks.contains(lo-1) { pen += 1 }
        if allRanks.contains(hi+1) { pen += 1 }
        return pen
    }
    static func flushPenalty(_ held: [Card], in hand: [Card]) -> Int {
        let s = Dictionary(grouping: hand, by: \.suit).mapValues { $0.count }
        guard let suit = held.first?.suit else { return 0 }
        let countSuit = s[suit] ?? 0
        return max(0, countSuit - held.count)
    }
    
    // MARK: Category
    static func category(for holdIdxs: [Int], in hand: [Card]) -> StrategyCategory {
        let held = holdIdxs.map { hand[$0] }
        if held.count == 5, isPatHand(held) { return .madeHand }
        
        let ranks = held.map(\.rank)
        
        // Top tier patterns
        if isFourToRoyal(held) { return .fourToRoyal }
        if isFourToStraightFlush(held) { return .fourToStraightFlush }
        
        // Distinct made-ish partials
        if held.count == 3, hasTrips(ranks) { return .trips }              // Keep 3
        if held.count == 4, isTwoPairRanks(ranks) { return .twoPairHold } // Keep both pairs
        
        // Pairs / trips fallback
        if hasTrips(ranks) { return .trips }
        if hasPair(ranks, minRank: 11) { return .highPair }
        
        // 3 to Royal strong
        if isThreeToRoyalStrong(held) { return .threeToRoyalStrong }
        
        // 4 to Flush
        if isFourToFlush(held) { return .fourToFlush }
        
        // Low pair
        if hasLowPair(ranks) { return .lowPair }
        
        // 4 to Outside Straight (with light penalty)
        if isFourToOutsideStraight(held) {
            let pen = straightPenalty(held, in: hand)
            if pen <= 1 { return .fourToOutsideStraight }
        }
        
        // 3 to Straight Flush Type A
        if isThreeToStraightFlushTypeA(held) { return .threeToStraightFlushTypeA }
        
        // AKQJ unsuited blocks
        if AKQJUnsuitedBlock(held) { return .AKQJUnsuited }
        
        // 2 suited highs (penalty check)
        if twoHighSuited(held) {
            let pen = flushPenalty(held, in: hand)
            if pen <= 1 { return .twoSuitedHigh }
        }
        
        // 3 to Royal weak
        if isThreeToRoyalWeak(held) { return .threeToRoyalWeak }
        
        // 3 to Straight Flush Type B
        if isThreeToStraightFlushTypeB(held) { return .threeToStraightFlushTypeB }
        
        // 2 high unsuited
        if twoHighUnsuited(held) { return .twoHighUnsuited }
        
        // 4 to Inside Straight
        if isFourToInsideStraight(held) { return .fourToInsideStraight }
        
        // Single highs
        if ranks.contains(14) && ranks.count == 1 { return .oneHighAce }
        if ranks.count == 1, isHigh(ranks.first!) { return .oneHighOther }
        
        return .trash
    }
    
    // MARK: Apply hierarchy then EV tiebreakers
    static func applyHierarchy(_ rows: inout [EVResultModel], hand: [Card]) {
        rows.sort { a, b in
            let ca = category(for: a.holdIndices, in: hand)
            let cb = category(for: b.holdIndices, in: hand)
            if ca != cb { return ca.rawValue < cb.rawValue }
            if abs(a.ev - b.ev) > 1e-9 { return a.ev > b.ev }
            if a.holdIndices.count != b.holdIndices.count { return a.holdIndices.count < b.holdIndices.count }
            return a.holdIndices.lexicographicallyPrecedes(b.holdIndices)
        }
        if let best = rows.first?.ev, best > 0 {
            for i in rows.indices {
                let cat = category(for: rows[i].holdIndices, in: hand)
                rows[i] = EVResultModel(
                    holdIndices: rows[i].holdIndices,
                    minPayout: rows[i].minPayout,
                    maxPayout: rows[i].maxPayout,
                    ev: rows[i].ev,
                    evPct: min(100, (rows[i].ev / best) * 100.0),
                    title: rows[i].title,
                    strategyLabel: label(cat),
                    isEstimate: rows[i].isEstimate
                )
            }
        } else {
            for i in rows.indices {
                let cat = category(for: rows[i].holdIndices, in: hand)
                rows[i] = EVResultModel(
                    holdIndices: rows[i].holdIndices,
                    minPayout: rows[i].minPayout,
                    maxPayout: rows[i].maxPayout,
                    ev: rows[i].ev,
                    evPct: rows[i].evPct,
                    title: rows[i].title,
                    strategyLabel: label(cat),
                    isEstimate: rows[i].isEstimate
                )
            }
        }
    }
}

// MARK: - EV Result Model

struct EVResultModel: Identifiable {
    let id = UUID()
    let holdIndices: [Int]
    let minPayout: Int
    let maxPayout: Int
    let ev: Double
    let evPct: Double
    let title: String
    let strategyLabel: String
    let isEstimate: Bool
}

enum GamePhase { case idle, dealt, roundComplete }

// MARK: - ViewModel

@MainActor
class PokerTrainerViewModel: ObservableObject {
    @Published var deck = Deck()
    @Published var hand: [Card] = []
    @Published var holds: [Bool] = Array(repeating: false, count: 5)
    @Published var winningCards: [Bool] = Array(repeating: false, count: 5)
    
    @Published var credits: Int = 1000
    @Published var message = "Tap Deal"
    @Published var results: [EVResultModel] = []
    @Published var phase: GamePhase = .idle
    @Published var coinBet: Int = 5
    
    @Published var multiResults: [(cards: [Card], rank: HandRank, payout: Int, wins: [Bool])] = []
    
    @Published var totalIn: Int = 0
    @Published var totalOut: Int = 0
    var rtpPercent: Double { totalIn == 0 ? 0 : (Double(totalOut) * 100.0 / Double(totalIn)) }
    
    // Stable 2-line UI summary
    @Published var lastPayoutTotal: Int = 0
    @Published var lastMainRank: HandRank? = nil
    @Published var lastMainPayout: Int = 0
    
    let maxDisplay = 4
    let handsCount = 10
    
    private var evTask: Task<Void, Never>?
    
    init() { deck.shuffle() }
    deinit { evTask?.cancel() }
    
    private func cancelEVTask() { evTask?.cancel(); evTask = nil }
    
    func deal() {
        cancelEVTask()
        let totalBet = coinBet * handsCount
        guard credits >= totalBet else {
            message = "Not enough credits for \(handsCount)x\(coinBet)"
            return
        }
        credits -= totalBet
        totalIn += totalBet
        deck = Deck(); deck.shuffle()
        hand = deck.draw(5)
        holds = Array(repeating: false, count: 5)
        winningCards = Array(repeating: false, count: 5)
        results = []; multiResults = []
        lastPayoutTotal = 0; lastMainRank = nil; lastMainPayout = 0
        phase = .dealt
        message = "Estimating EV…"
        calculateMonteCarloEVSuggestions()
    }
    
    func toggleHold(index: Int) {
        guard phase == .dealt else { return }
        holds[index].toggle()
    }
    
    func draw() {
        cancelEVTask()
        guard phase == .dealt else { return }
        winningCards = Array(repeating: false, count: hand.count)
        
        let replaceIndices = holds.indices.filter { !holds[$0] }
        let baseDeck = deck
        let originalDealt = hand
        multiResults = []
        var total = 0
        
        for _ in 0..<handsCount {
            var d = baseDeck
            d.shuffle()
            var h = originalDealt
            let replacements = d.draw(replaceIndices.count)
            for (i, idx) in replaceIndices.enumerated() { h[idx] = replacements[i] }
            let rank = HandEvaluator.evaluate(h)
            let payout = payoutFor(rank: rank, coins: coinBet)
            let flags = winningMask(for: h, rank: rank)
            total += payout
            multiResults.append((cards: h, rank: rank, payout: payout, wins: flags))
        }
        
        multiResults.sort {
            if $0.payout != $1.payout { return $0.payout > $1.payout }
            return handRankValue($0.rank) > handRankValue($1.rank)
        }
        if let top = multiResults.first {
            hand = top.cards
            winningCards = top.wins
        }
        
        credits += total
        totalOut += total
        
        // Stable summary
        lastPayoutTotal = total
        if let main = multiResults.first {
            lastMainRank = main.rank
            lastMainPayout = main.payout
        } else {
            lastMainRank = nil
            lastMainPayout = 0
        }
        
        phase = .roundComplete
        results = []
        message = "Round complete"
    }
    
    // MARK: MC first
    
    func calculateMonteCarloEVSuggestions() {
        guard hand.count == 5 else { return }
        cancelEVTask()
        
        let handSnapshot = hand
        let remainder = deck.cards
        let coins = coinBet
        let masks = EVEngine.allHoldMasks()
        let maxRows = maxDisplay
        
        evTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var rng = SystemRandomNumberGenerator()
            let samplesPerHold = 3000
            
            var mcRows: [EVResultModel] = []
            var bestEV = -1.0
            var bestHold: [Int] = []
            for mask in masks {
                if Task.isCancelled { return }
                let ev = EVEngine.monteCarloEVForHold(
                    holdIdxs: mask, hand: handSnapshot, remainder: remainder, coins: coins,
                    samples: samplesPerHold, rng: &rng
                )
                if ev > bestEV { bestEV = ev; bestHold = mask }
                mcRows.append(EVResultModel(
                    holdIndices: mask, minPayout: 0, maxPayout: 0,
                    ev: ev, evPct: 0,
                    title: EVEngine.describeHold(indices: mask, hand: handSnapshot),
                    strategyLabel: "",
                    isEstimate: true
                ))
            }
            
            var sorted = mcRows
            Strategy.applyHierarchy(&sorted, hand: handSnapshot)
            
            await MainActor.run {
                if self.phase != .dealt { return }
                self.holds = Array(repeating: false, count: 5)
                for i in bestHold { self.holds[i] = true }
                self.results = Array(sorted.prefix(maxRows))
                if let top = self.results.first {
                    self.message = "\(top.title)  [\(top.strategyLabel)]  " + String(format: "EV %.3f (est.)", top.ev)
                } else {
                    self.message = "EV estimates ready"
                }
            }
        }
    }
    
    // MARK: Exact on demand for visible rows
    
    func computeExactForVisibleSuggestions() {
        guard phase == .dealt, !results.isEmpty else { return }
        cancelEVTask()
        
        let targetMasks = results.map { $0.holdIndices }
        let handSnapshot = hand
        let remainder = deck.cards
        let coins = coinBet
        
        func key(_ a: [Int]) -> String { a.map(String.init).joined(separator: "-") }
        let exactMasks = targetMasks.filter { (5 - $0.count) <= 3 }
        let exactSet = Set(exactMasks.map(key))
        let allSet = Set(targetMasks.map(key))
        let skipKeys = allSet.subtracting(exactSet)
        let skipMasks = targetMasks.filter { skipKeys.contains(key($0)) }
        
        evTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var exRows: [EVResultModel] = []
            var bestEV: Double = -1.0
            var bestHold: [Int] = []
            
            for (i, mask) in exactMasks.enumerated() {
                if Task.isCancelled { return }
                let (ev, minPay, maxPay) = EVEngine.exactEVForHold(
                    holdIdxs: mask, hand: handSnapshot, remainder: remainder, coins: coins
                )
                if ev > bestEV { bestEV = ev; bestHold = mask }
                exRows.append(EVResultModel(
                    holdIndices: mask, minPayout: minPay, maxPayout: maxPay,
                    ev: ev, evPct: 0,
                    title: EVEngine.describeHold(indices: mask, hand: handSnapshot),
                    strategyLabel: "",
                    isEstimate: false
                ))
                if i % 2 == 1 {
                    await MainActor.run {
                        if self.phase == .dealt {
                            self.message = "Computing exact… (\(i + 1)/\(exactMasks.count))"
                        }
                    }
                }
            }
            
            if !skipMasks.isEmpty {
                var rng = SystemRandomNumberGenerator()
                for mask in skipMasks {
                    if Task.isCancelled { return }
                    let evMC = EVEngine.monteCarloEVForHold(
                        holdIdxs: mask, hand: handSnapshot, remainder: remainder, coins: coins,
                        samples: 30_000, rng: &rng
                    )
                    if evMC > bestEV { bestEV = evMC; bestHold = mask }
                    exRows.append(EVResultModel(
                        holdIndices: mask, minPayout: 0, maxPayout: 0,
                        ev: evMC, evPct: 0,
                        title: EVEngine.describeHold(indices: mask, hand: handSnapshot),
                        strategyLabel: "",
                        isEstimate: true
                    ))
                }
            }
            
            var catRows = exRows
            Strategy.applyHierarchy(&catRows, hand: handSnapshot)
            
            await MainActor.run {
                if self.phase != .dealt { return }
                self.holds = Array(repeating: false, count: 5)
                for i in bestHold { self.holds[i] = true }
                self.results = catRows
                if let top = self.results.first {
                    if top.isEstimate {
                        self.message = "\(top.title)  [\(top.strategyLabel)]  " + String(format: "EV %.3f (MC)", top.ev)
                    } else {
                        self.message = "\(top.title)  [\(top.strategyLabel)]  " +
                        String(format: "EV %.3f  |  $%d–$%d", top.ev, top.minPayout, top.maxPayout)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func winningMask(for cards: [Card], rank: HandRank) -> [Bool] {
        var flags = Array(repeating: false, count: cards.count)
        let counts = Dictionary(grouping: cards, by: { $0.rank }).mapValues { $0.count }
        switch rank {
        case .royalFlush, .straightFlush, .flush, .straight:
            for i in cards.indices { flags[i] = true }
        case .fourOfAKind:
            if let r = counts.first(where: { $0.value == 4 })?.key {
                for i in cards.indices where cards[i].rank == r { flags[i] = true }
            }
        case .fullHouse:
            if let t = counts.first(where: { $0.value == 3 })?.key {
                for i in cards.indices where cards[i].rank == t { flags[i] = true }
            }
            if let p = counts.first(where: { $0.value == 2 })?.key {
                for i in cards.indices where cards[i].rank == p { flags[i] = true }
            }
        case .threeOfAKind:
            if let t = counts.first(where: { $0.value == 3 })?.key {
                for i in cards.indices where cards[i].rank == t { flags[i] = true }
            }
        case .twoPair:
            let pairs = counts.filter { $0.value == 2 }.map { $0.key }
            for r in pairs { for i in cards.indices where cards[i].rank == r { flags[i] = true } }
        case .jacksOrBetter:
            if let p = counts.first(where: { $0.value == 2 && $0.key >= 11 })?.key {
                for i in cards.indices where cards[i].rank == p { flags[i] = true }
            }
        case .nothing:
            break
        }
        return flags
    }
    
    private func handRankValue(_ rank: HandRank) -> Int {
        switch rank {
        case .royalFlush: return 10
        case .straightFlush: return 9
        case .fourOfAKind: return 8
        case .fullHouse: return 7
        case .flush: return 6
        case .straight: return 5
        case .threeOfAKind: return 4
        case .twoPair: return 3
        case .jacksOrBetter: return 2
        case .nothing: return 1
        }
    }
    
    func selectSuggestion(_ r: EVResultModel) {
        holds = Array(repeating: false, count: 5)
        for i in r.holdIndices { holds[i] = true }
        if r.isEstimate {
            message = "\(r.title)  [\(r.strategyLabel)]  " + String(format: "EV %.3f (est.)", r.ev)
        } else {
            message = "\(r.title)  [\(r.strategyLabel)]  " +
            String(format: "EV %.3f  |  $%d–$%d", r.ev, r.minPayout, r.maxPayout)
        }
    }
}

// MARK: - Views: Cards

struct CardBackView: View {
    let w: CGFloat, h: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.8))
                .frame(width: w, height: h)
            ForEach(0..<8, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 2, height: h)
                    .rotationEffect(.degrees(Double(i) * 15))
            }
        }
    }
}

struct CardViewSlot: View {
    let card: Card
    @Binding var isHeld: Bool
    @Binding var isWinning: Bool
    let w: CGFloat, h: CGFloat
    @State private var pulse = false
    
    var active: Bool { isHeld || isWinning }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.white).frame(width: w, height: h)
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderGradient(), lineWidth: active ? 3 : 1)
                .frame(width: w, height: h)
            if active {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderGradient(), lineWidth: 6)
                    .blur(radius: 7 + (pulse ? 5 : 0))
                    .opacity(0.5)
                    .frame(width: w, height: h)
            }
            Text(card.shortName)
                .font(.title3).bold()
                .foregroundColor(card.suit == .hearts || card.suit == .diamonds ? .red : .black)
        }
        .onAppear { pulse = active }
        .onChange(of: active) { newVal in pulse = newVal }
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
    }
    
    private func borderGradient() -> LinearGradient {
        if isWinning {
            return LinearGradient(colors: [.green, .green.opacity(0.25), .green],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if isHeld {
            return LinearGradient(colors: [.yellow, .orange, .yellow],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [.gray.opacity(0.6), .gray.opacity(0.4)],
                                  startPoint: .top, endPoint: .bottom)
        }
    }
}

struct MiniCard: View {
    let card: Card
    let isWinning: Bool
    let w: CGFloat, h: CGFloat
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.white)
            RoundedRectangle(cornerRadius: 6).strokeBorder(isWinning ? .green : .gray, lineWidth: 2)
            VStack(spacing: 0) {
                Text(rankText).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor)
                Text(suitText).font(.system(size: 10)).foregroundColor(textColor)
            }
        }
        .frame(width: w, height: h)
    }
    private var rankText: String {
        switch card.rank {
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        case 14: return "A"
        default: return "\(card.rank)"
        }
    }
    private var suitText: String { card.suit.rawValue }
    private var textColor: Color { (card.suit == .hearts || card.suit == .diamonds) ? .red : .black }
}

struct MiniHoldStrip: View {
    let hand: [Card]
    let holdIndices: [Int]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { idx in
                if holdIndices.contains(idx) {
                    MiniCard(card: hand[idx], isWinning: false, w: 20, h: 28)
                } else {
                    CardBackView(w: 20, h: 28)
                }
            }
        }
    }
}

struct MiniHandView: View {
    let cards: [Card]
    let wins: [Bool]
    let rank: HandRank
    let payout: Int
    let cardW: CGFloat, cardH: CGFloat
    let spacing: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: spacing) {
                ForEach(cards.indices, id: \.self) { i in
                    MiniCard(card: cards[i],
                             isWinning: wins.indices.contains(i) ? wins[i] : false,
                             w: cardW, h: cardH)
                }
            }
            VStack(spacing: 0) {
                Text(rank.rawValue).font(.caption2.weight(.semibold)).foregroundColor(.white)
                Text("$\(payout)").font(.caption2.monospaced()).foregroundColor(.yellow)
            }
        }
    }
}

// MARK: - Heat Bar

struct HeatBar: View {
    let pct: Double
    let isEstimate: Bool
    
    var colorForEV: Color {
        switch pct {
        case 95...100: return .green
        case 85..<95:  return .yellow
        default:       return .red
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorForEV)
                    .frame(width: max(0, min(1, pct / 100.0)) * geo.size.width)
            }
        }
        .frame(height: 10)
        .cornerRadius(4)
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var vm = PokerTrainerViewModel()
    
    enum UIMode: String, CaseIterable { case trainer = "Trainer Mode", casino = "Casino Mode" }
    @State private var uiMode: UIMode = .trainer
    
    @State private var lockedWidth: CGFloat? = nil
    @State private var creditPulse: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let pad: CGFloat = 20
            let base = lockedWidth ?? min(max(geo.size.width, 320), 428)
            let available = base - pad * 2
            let cardW = min(76, max(48, (available - spacing * 4) / 5))
            let cardH = cardW * 1.45
            
            let gridSpacing: CGFloat = 18
            let tileGap: CGFloat = 6
            let colWidth = (available - 2 * gridSpacing) / 3
            let miniSpacing: CGFloat = 5
            let miniCardW = ((colWidth - tileGap * 2) - miniSpacing * 4) / 4.1
            let miniCardH = miniCardW * 1.55
            
            ZStack(alignment: .top) {
                Color(red: 0.03, green: 0.15, blue: 0.05)
                    .ignoresSafeArea()
                    .overlay(
                        RadialGradient(colors: [.black.opacity(0.18), .clear],
                                       center: .center, startRadius: 10, endRadius: 600)
                        .blendMode(.multiply)
                    )
                
                VStack(spacing: 10) {
                    // Title + Mode Toggle
                    VStack(spacing: 6) {
                        Text("🎰 10-PLAY VIDEO POKER 🎰")
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundStyle(
                                LinearGradient(colors: [.yellow, .orange, .red],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .padding(.top, 10)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Picker("", selection: $uiMode) {
                            ForEach(UIMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.horizontal, 6)
                        .accessibilityIdentifier("TrainerCasinoToggle")
                    }
                    
                    // Credits + RTP
                    VStack(spacing: 2) {
                        Text("Credits: $\(vm.credits)")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .scaleEffect(creditPulse ? 1.06 : 1.0)
                            .animation(.easeOut(duration: 0.25), value: creditPulse)
                        Text(String(format: "RTP: %.1f%%  (in: %d  out: %d)", vm.rtpPercent, vm.totalIn, vm.totalOut))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                            .monospacedDigit()
                    }
                    .onChange(of: vm.credits) { _ in
                        creditPulse = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { creditPulse = false }
                    }
                    
                    // Hand row
                    HStack(spacing: spacing) {
                        if vm.phase == .idle {
                            ForEach(0..<5, id: \.self) { _ in CardBackView(w: cardW, h: cardH) }
                        } else {
                            ForEach(Array(vm.hand.indices), id: \.self) { idx in
                                CardViewSlot(card: vm.hand[idx],
                                             isHeld: $vm.holds[idx],
                                             isWinning: $vm.winningCards[idx],
                                             w: cardW, h: cardH)
                                .onTapGesture { if vm.phase == .dealt { vm.toggleHold(index: idx) } }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    
                    // Stable two-line status
                    VStack(spacing: 2) {
                        Text(statusTopText)   // no [Trainer]/[Casino] tag here anymore
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 18)
                        Text(statusBottomText) // mode remains shown here
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 16)
                    }
                    .padding(.horizontal)
                    
                    // Bet buttons
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { b in
                            Button(action: {
                                vm.coinBet = b
                                if vm.phase == .dealt { vm.calculateMonteCarloEVSuggestions() }
                            }) {
                                Text("\(b)x")
                                    .font(.footnote).bold()
                                    .frame(width: 48, height: 30)
                                    .background(vm.coinBet == b ? Color.yellow : Color.gray.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }
                        Text("Total: \(vm.coinBet)×10 = \(vm.coinBet * 10)")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.footnote)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    
                    // Deal / Draw
                    Button(action: {
                        switch vm.phase {
                        case .idle, .roundComplete: vm.deal()
                        case .dealt: vm.draw()
                        }
                    }) {
                        Text(vm.phase == .dealt
                             ? (uiMode == .casino ? "Draw (10-Play) — Casino" : "Draw (10-Play) — Trainer")
                             : (uiMode == .casino ? "Deal — Casino" : "Deal — Trainer"))
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.yellow)
                        .cornerRadius(14)
                        .shadow(color: .yellow.opacity(0.35), radius: 8, x: 0, y: 3)
                    }
                    .padding(.horizontal)
                    
                    // Suggested holds
                    if vm.phase == .dealt, !vm.results.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Suggested holds")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.leading, 2)
                            
                            VStack(spacing: 6) {
                                ForEach(Array(vm.results.prefix(4)).enumerated().map({ $0 }), id: \.element.id) { index, r in
                                    let isBest = index == 0
                                    VStack(spacing: 4) {
                                        HStack(spacing: 8) {
                                            MiniHoldStrip(hand: vm.hand, holdIndices: r.holdIndices)
                                                .frame(width: 110, alignment: .leading)
                                            
                                            Text(r.strategyLabel)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                            
                                            Spacer()
                                            
                                            HeatBar(pct: r.evPct, isEstimate: r.isEstimate)
                                                .frame(width: 50, height: 10)
                                                .cornerRadius(4)
                                        }
                                        
                                        HStack {
                                            if isBest {
                                                Text("BEST")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.yellow.opacity(0.95))
                                                    .cornerRadius(4)
                                                    .shadow(color: .yellow.opacity(0.6), radius: 5)
                                            }
                                            
                                            Spacer()
                                            
                                            Text(r.isEstimate
                                                 ? String(format: "EV %.3f (est.)", r.ev)
                                                 : String(format: "EV %.3f", r.ev))
                                            .font(.caption2.monospaced())
                                            .foregroundColor(.white.opacity(0.9))
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        ZStack {
                                            if isBest {
                                                Color.yellow.opacity(0.16)
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.yellow.opacity(0.85), lineWidth: 2)
                                                    .shadow(color: Color.yellow.opacity(0.55), radius: 7)
                                            } else {
                                                Color.white.opacity(0.08)
                                            }
                                        }
                                    )
                                    .cornerRadius(8)
                                    .opacity(isBest ? 1.0 : 0.88)
                                    .contentShape(Rectangle())
                                    .onTapGesture { vm.selectSuggestion(r) }
                                }
                                
                                Button(action: { vm.computeExactForVisibleSuggestions() }) {
                                    Text("Show exact EV for these holds")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .background(Color.gray.opacity(0.22))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
                                        .cornerRadius(14)
                                }
                                .disabled(vm.results.allSatisfy { !$0.isEstimate })
                                .opacity(vm.results.allSatisfy { !$0.isEstimate } ? 0.5 : 1)
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                        }
                        .padding(.horizontal, 6)
                    }
                    
                    // Side hands grid after round
                    if vm.phase == .roundComplete, vm.multiResults.count >= 10 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("10-Play side hands (2–10)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.leading)
                            
                            let side = Array(vm.multiResults.dropFirst())
                            ScrollView {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3),
                                          spacing: gridSpacing) {
                                    ForEach(side.indices, id: \.self) { i in
                                        MiniHandView(cards: side[i].cards,
                                                     wins: side[i].wins,
                                                     rank: side[i].rank,
                                                     payout: side[i].payout,
                                                     cardW: miniCardW, cardH: miniCardH,
                                                     spacing: miniSpacing)
                                        .padding(8)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                        .padding(tileGap)
                                    }
                                }
                                          .padding(.horizontal)
                                          .padding(.top, 6)
                            }
                            .frame(maxHeight: 320)
                        }
                    } else {
                        Spacer(minLength: 8)
                    }
                }
                .frame(width: base)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, pad)
                .padding(.bottom, 12)
            }
            .onAppear {
                if lockedWidth == nil {
                    lockedWidth = min(max(geo.size.width, 320), 428)
                }
            }
        }
    }
    
    // Computed status lines for stable UI
    private var statusTopText: String {
        switch vm.phase {
        case .idle: return vm.message            // tag removed
        case .dealt: return vm.message           // tag removed
        case .roundComplete: return "10-Play payout: $\(vm.lastPayoutTotal)"
        }
    }
    
    private var statusBottomText: String {
        switch vm.phase {
        case .idle: return uiMode.rawValue
        case .dealt: return uiMode.rawValue
        case .roundComplete:
            if let r = vm.lastMainRank {
                return "Main Hand: \(r.rawValue) ($\(vm.lastMainPayout))"
            } else {
                return "Main Hand: —"
            }
        }
    }
}
