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