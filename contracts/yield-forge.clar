;; Title: YieldForge - Bitcoin-Native Yield Aggregation Protocol
;; Summary: A smart contract for automated yield farming with risk-managed protocol allocation on Stacks L2
;; Description:
;; YieldForge is a non-custodial yield aggregator that enables Bitcoin-centric DeFi strategies through
;; Stacks Layer 2. The protocol automatically allocates user funds across multiple lending platforms
;; based on customizable risk profiles (Conservative/Moderate/High), while implementing institutional-grade
;; security features including:
;; - Cross-protocol position management
;; - Timelocked withdrawals
;; - Insurance fund protection
;; - Automated yield compounding
;; - Protocol whitelisting system
;; - Dynamic APY optimization
;;
;; Designed for Bitcoin compatibility, YieldForge implements SIP-009 compliant assets and enables
;; trustless participation in Bitcoin DeFi ecosystems through Stacks-secured smart contracts.
;; The protocol earns revenue through performance-based fees (1%) and insurance contributions (0.5%),
;; creating sustainable incentives for long-term ecosystem growth.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-PROTOCOL-NOT-WHITELISTED (err u1001))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1002))
(define-constant ERR-PROTOCOL-ALREADY-EXISTS (err u1003))
(define-constant ERR-INVALID-RISK-PROFILE (err u1004))
(define-constant ERR-WITHDRAWAL-IN-PROGRESS (err u1005))
(define-constant ERR-WITHDRAWAL-NOT-READY (err u1006))
(define-constant ERR-ZERO-AMOUNT (err u1007))
(define-constant ERR-INVALID-PROTOCOL-ID (err u1008))
(define-constant ERR-TIMELOCK-NOT-EXPIRED (err u1009))
(define-constant ERR-PROTOCOL-NOT-ACTIVE (err u1010))

;; Constants
(define-constant RISK_CONSERVATIVE u1)
(define-constant RISK_MODERATE u2)
(define-constant RISK_HIGH u3)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var insurance-fund-address principal tx-sender)
(define-data-var insurance-fee-bps uint u50) ;; 0.5% fee for insurance
(define-data-var performance-fee-bps uint u100) ;; 1% performance fee
(define-data-var next-protocol-id uint u1)
(define-data-var next-strategy-id uint u1)
(define-data-var next-withdrawal-id uint u1)
(define-data-var contract-paused bool false)

;; Data maps
(define-map protocols
  uint ;; protocol ID
  {
    name: (string-ascii 64),
    contract-address: principal,
    token-address: principal,
    risk-level: uint,
    active: bool,
    total-tvl: uint,
    current-apy-bps: uint
  }
)

(define-map user-deposits
  {user: principal, protocol-id: uint}
  {
    amount: uint,
    shares: uint,
    last-compound: uint,
    deposit-height: uint
  }
)

(define-map user-totals
  principal
  {
    total-deposited: uint,
    total-withdrawn: uint,
    total-earned: uint,
    conservative-allocation: uint, ;; percentage in basis points (100 = 1%)
    moderate-allocation: uint,
    high-allocation: uint
  }
)

(define-map withdrawal-requests
  uint ;; withdrawal ID
  {
    user: principal,
    protocol-id: uint,
    amount: uint,
    request-height: uint,
    timelock-blocks: uint,
    status: (string-ascii 20) ;; "pending", "processed", "cancelled"
  }
)

(define-map protocol-allocations
  {strategy-id: uint, risk-level: uint}
  {
    protocol-id: uint,
    allocation-percentage: uint  ;; in basis points (100 = 1%)
  }
)

;; Authorization functions
(define-read-only (get-contract-owner)
  (ok (var-get contract-owner))
)

(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

(define-public (set-insurance-fund-address (new-address principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set insurance-fund-address new-address))
  )
)

(define-public (set-insurance-fee (new-fee-bps uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (< new-fee-bps u1000) (err u1011)) ;; Max 10%
    (ok (var-set insurance-fee-bps new-fee-bps))
  )
)

(define-public (set-performance-fee (new-fee-bps uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (< new-fee-bps u2000) (err u1012)) ;; Max 20%
    (ok (var-set performance-fee-bps new-fee-bps))
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-paused true))
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-paused false))
  )
)

;; Protocol management
(define-public (add-protocol 
    (name (string-ascii 64)) 
    (contract-address principal) 
    (token-address principal) 
    (risk-level uint)
    (apy-bps uint))
  (let 
    (
      (protocol-id (var-get next-protocol-id))
    )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq risk-level RISK_CONSERVATIVE) 
                 (is-eq risk-level RISK_MODERATE) 
                 (is-eq risk-level RISK_HIGH)) ERR-INVALID-RISK-PROFILE)
    (asserts! (is-none (get-protocol-by-name name)) ERR-PROTOCOL-ALREADY-EXISTS)
    
    (map-set protocols protocol-id {
      name: name,
      contract-address: contract-address,
      token-address: token-address,
      risk-level: risk-level,
      active: true,
      total-tvl: u0,
      current-apy-bps: apy-bps
    })
    
    (var-set next-protocol-id (+ protocol-id u1))
    (ok protocol-id)
  )
)

(define-public (update-protocol-status (protocol-id uint) (active bool))
  (let
    (
      (protocol (unwrap! (map-get? protocols protocol-id) ERR-INVALID-PROTOCOL-ID))
    )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    (map-set protocols protocol-id (merge protocol {active: active}))
    (ok true)
  )
)

(define-public (update-protocol-apy (protocol-id uint) (new-apy-bps uint))
  (let
    (
      (protocol (unwrap! (map-get? protocols protocol-id) ERR-INVALID-PROTOCOL-ID))
    )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    (map-set protocols protocol-id (merge protocol {current-apy-bps: new-apy-bps}))
    (ok true)
  )
)

;; Helper functions
(define-read-only (get-protocol-by-id (protocol-id uint))
  (map-get? protocols protocol-id)
)

(define-read-only (get-protocol-by-name (name (string-ascii 64)))
  (let
    (
      (protocol-count (var-get next-protocol-id))
      (result (fold find-protocol-by-name {found: false, id: u0} (list-protocols protocol-count)))
    )
    (if (get found result)
      (map-get? protocols (get id result))
      none
    )
  )
)

(define-private (find-protocol-by-name (id uint) (result {found: bool, id: uint}) (name-to-find (string-ascii 64)))
  (let
    (
      (protocol (unwrap! (map-get? protocols id) result))
    )
    (if (is-eq (get name protocol) name-to-find)
      {found: true, id: id}
      result
    )
  )
)

(define-private (list-protocols (count uint))
  (map to-uint (get-range-at u0 count))
)

(define-private (to-uint (item uint)) 
  item
)

(define-private (get-range-at (start uint) (end uint))
  (if (< start end)
    (unwrap-panic (as-max-len? (append (get-range-at start (- end u1)) (- end u1)) u100))
    (list)
  )
)

;; User risk profile management
(define-public (set-user-risk-profile 
    (conservative-allocation uint) 
    (moderate-allocation uint) 
    (high-allocation uint))
  (let
    (
      (current-user-totals (default-to {
        total-deposited: u0,
        total-withdrawn: u0,
        total-earned: u0,
        conservative-allocation: u0,
        moderate-allocation: u0,
        high-allocation: u0
      } (map-get? user-totals tx-sender)))
      (total-allocation (+ (+ conservative-allocation moderate-allocation) high-allocation))
    )
    (asserts! (not (var-get contract-paused)) (err u1013))
    (asserts! (is-eq total-allocation u10000) (err u1014)) ;; Must sum to 100% (10000 basis points)
    
    (map-set user-totals tx-sender (merge current-user-totals {
      conservative-allocation: conservative-allocation,
      moderate-allocation: moderate-allocation,
      high-allocation: high-allocation
    }))
    
    (ok true)
  )
)

(define-read-only (get-user-risk-profile (user principal))
  (default-to {
    conservative-allocation: u3333, ;; Default to balanced 33.33% each
    moderate-allocation: u3333,
    high-allocation: u3334
  } 
  (map-get? user-totals user))
)

;; Deposit functions
(define-public (deposit (protocol-id uint) (amount uint) (token principal))
  (let
    (
      (protocol (unwrap! (map-get? protocols protocol-id) ERR-INVALID-PROTOCOL-ID))
      (user-deposit (default-to {
        amount: u0, 
        shares: u0,
        last-compound: block-height,
        deposit-height: block-height
      } (map-get? user-deposits {user: tx-sender, protocol-id: protocol-id})))
      (current-user-totals (default-to {
        total-deposited: u0,
        total-withdrawn: u0,
        total-earned: u0,
        conservative-allocation: u3333,
        moderate-allocation: u3333,
        high-allocation: u3334
      } (map-get? user-totals tx-sender)))
      (shares-to-mint (calculate-shares-to-mint amount protocol-id))
    )
    (asserts! (not (var-get contract-paused)) (err u1013))
    (asserts! (> amount u0) ERR-ZERO-AMOUNT)
    (asserts! (get active protocol) ERR-PROTOCOL-NOT-ACTIVE)
    (asserts! (is-eq token (get token-address protocol)) (err u1015))
    
    ;; Transfer tokens from user to this contract
    (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender) none))
    
    ;; Update protocol TVL
    (map-set protocols protocol-id (merge protocol {
      total-tvl: (+ (get total-tvl protocol) amount)
    }))
    
    ;; Update user deposits
    (map-set user-deposits {user: tx-sender, protocol-id: protocol-id} {
      amount: (+ (get amount user-deposit) amount),
      shares: (+ (get shares user-deposit) shares-to-mint),
      last-compound: block-height,
      deposit-height: (if (is-eq (get amount user-deposit) u0) block-height (get deposit-height user-deposit))
    })
    
    ;; Update user totals
    (map-set user-totals tx-sender (merge current-user-totals {
      total-deposited: (+ (get total-deposited current-user-totals) amount)
    }))
    
    (ok shares-to-mint)
  )
)

(define-public (smart-deposit (amount uint) (token principal))
  (let
    (
      (user-profile (get-user-risk-profile tx-sender))
      (conservative-amount (/ (* amount (get conservative-allocation user-profile)) u10000))
      (moderate-amount (/ (* amount (get moderate-allocation user-profile)) u10000))
      (high-amount (- amount (+ conservative-amount moderate-amount)))
      (best-conservative-protocol (get-best-protocol-in-risk-level RISK_CONSERVATIVE))
      (best-moderate-protocol (get-best-protocol-in-risk-level RISK_MODERATE))
      (best-high-protocol (get-best-protocol-in-risk-level RISK_HIGH))
    )
    (asserts! (not (var-get contract-paused)) (err u1013))
    (asserts! (> amount u0) ERR-ZERO-AMOUNT)
    
    ;; Deposit into best protocols based on risk profile
    (if (and (> conservative-amount u0) (is-some best-conservative-protocol))
      (try! (deposit (unwrap-panic best-conservative-protocol) conservative-amount token))
      true
    )
    
    (if (and (> moderate-amount u0) (is-some best-moderate-protocol))
      (try! (deposit (unwrap-panic best-moderate-protocol) moderate-amount token))
      true
    )
    
    (if (and (> high-amount u0) (is-some best-high-protocol))
      (try! (deposit (unwrap-panic best-high-protocol) high-amount token))
      true
    )
    
    (ok true)
  )
)

(define-private (calculate-shares-to-mint (amount uint) (protocol-id uint))
  (let
    (
      (protocol (unwrap-panic (map-get? protocols protocol-id)))
      (total-tvl (get total-tvl protocol))
    )
    (if (is-eq total-tvl u0)
      amount ;; First deposit, 1:1 shares
      (/ (* amount u1000000) (/ total-tvl u1000000)) ;; Scale to avoid precision issues
    )
  )
)

;; Withdraw functions
(define-public (request-withdrawal (protocol-id uint) (amount uint))
  (let
    (
      (user-deposit (unwrap! (map-get? user-deposits {user: tx-sender, protocol-id: protocol-id}) ERR-INSUFFICIENT-BALANCE))
      (protocol (unwrap! (map-get? protocols protocol-id) ERR-INVALID-PROTOCOL-ID))
      (withdraw-id (var-get next-withdrawal-id))
      (timelock-blocks u144) ;; ~24 hours on Bitcoin (6 blocks per hour)
    )
    (asserts! (not (var-get contract-paused)) (err u1013))
    (asserts! (>= (get amount user-deposit) amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-ZERO-AMOUNT)
    
    ;; Create withdrawal request
    (map-set withdrawal-requests withdraw-id {
      user: tx-sender,
      protocol-id: protocol-id,
      amount: amount,
      request-height: block-height,
      timelock-blocks: timelock-blocks,
      status: "pending"
    })
    
    (var-set next-withdrawal-id (+ withdraw-id u1))
    (ok withdraw-id)
  )
)

(define-public (process-withdrawal (withdrawal-id uint))
  (let
    (
      (withdrawal (unwrap! (map-get? withdrawal-requests withdrawal-id) ERR-INVALID-PROTOCOL-ID))
      (user (get user withdrawal))
      (protocol-id (get protocol-id withdrawal))
      (amount (get amount withdrawal))
      (protocol (unwrap! (map-get? protocols protocol-id) ERR-INVALID-PROTOCOL-ID))
      (user-deposit (unwrap! (map-get? user-deposits {user: user, protocol-id: protocol-id}) ERR-INSUFFICIENT-BALANCE))
      (current-user-totals (default-to {
        total-deposited: u0,
        total-withdrawn: u0,
        total-earned: u0,
        conservative-allocation: u3333,
        moderate-allocation: u3333,
        high-allocation: u3334
      } (map-get? user-totals user)))
      (token-address (get token-address protocol))
      (shares-to-burn (/ (* amount (get shares user-deposit)) (get amount user-deposit)))
    )
    (asserts! (not (var-get contract-paused)) (err u1013))
    (asserts! (is-eq (get status withdrawal) "pending") (err u1016))
    (asserts! (>= block-height (+ (get request-height withdrawal) (get timelock-blocks withdrawal))) ERR-TIMELOCK-NOT-EXPIRED)
    (asserts! (>= (get amount user-deposit) amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Update protocol TVL
    (map-set protocols protocol-id (merge protocol {
      total-tvl: (- (get total-tvl protocol) amount)
    }))
    
    ;; Update user deposits
    (map-set user-deposits {user: user, protocol-id: protocol-id} {
      amount: (- (get amount user-deposit) amount),
      shares: (- (get shares user-deposit) shares-to-burn),
      last-compound: (get last-compound user-deposit),
      deposit-height: (get deposit-height user-deposit)
    })
    
    ;; Update user totals
    (map-set user-totals user (merge current-user-totals {
      total-withdrawn: (+ (get total-withdrawn current-user-totals) amount)
    }))
    
    ;; Update withdrawal status
    (map-set withdrawal-requests withdrawal-id (merge withdrawal {
      status: "processed"
    }))
    
    ;; Transfer tokens from contract to user
    (as-contract (contract-call? token-address transfer amount tx-sender user none))
  )
)