;; UltraDashboard - Decentralized Blockchain Monitoring Infrastructure
;; Core smart contract for monitoring node operations and rewards

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-stake (err u102))
(define-constant err-node-exists (err u103))
(define-constant err-node-not-found (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-already-claimed (err u107))

;; Minimum stake required to operate a monitoring node (100 ULD tokens)
(define-constant min-stake-amount u100000000)

;; Data Variables
(define-data-var total-staked uint u0)
(define-data-var total-nodes uint u0)
(define-data-var reward-pool uint u0)

;; Data Maps
(define-map monitoring-nodes
  principal
  {
    staked-amount: uint,
    registration-height: uint,
    active: bool,
    total-reports: uint,
    accuracy-score: uint,
    last-activity: uint
  }
)

(define-map anomaly-reports
  uint
  {
    reporter: principal,
    blockchain: (string-ascii 20),
    report-type: (string-ascii 50),
    severity: uint,
    timestamp: uint,
    verified: bool,
    reward-claimed: bool
  }
)

(define-map node-rewards
  principal
  {
    total-earned: uint,
    pending-rewards: uint,
    last-claim-height: uint
  }
)

(define-data-var report-nonce uint u0)

;; Read-only functions
(define-read-only (get-node-info (node principal))
  (map-get? monitoring-nodes node)
)

(define-read-only (get-node-rewards (node principal))
  (map-get? node-rewards node)
)

(define-read-only (get-anomaly-report (report-id uint))
  (map-get? anomaly-reports report-id)
)

(define-read-only (get-total-staked)
  (ok (var-get total-staked))
)

(define-read-only (get-total-nodes)
  (ok (var-get total-nodes))
)

(define-read-only (get-reward-pool)
  (ok (var-get reward-pool))
)

(define-read-only (is-active-node (node principal))
  (match (map-get? monitoring-nodes node)
    node-data (ok (get active node-data))
    (ok false)
  )
)

;; Public functions

;; Register as a monitoring node by staking tokens
(define-public (register-node (stake-amount uint))
  (let
    (
      (sender tx-sender)
      (current-height block-height)
    )
    (asserts! (>= stake-amount min-stake-amount) err-insufficient-stake)
    (asserts! (is-none (map-get? monitoring-nodes sender)) err-node-exists)
    
    ;; Record the stake (in production, this would transfer tokens)
    (map-set monitoring-nodes sender {
      staked-amount: stake-amount,
      registration-height: current-height,
      active: true,
      total-reports: u0,
      accuracy-score: u100,
      last-activity: current-height
    })
    
    (map-set node-rewards sender {
      total-earned: u0,
      pending-rewards: u0,
      last-claim-height: current-height
    })
    
    (var-set total-staked (+ (var-get total-staked) stake-amount))
    (var-set total-nodes (+ (var-get total-nodes) u1))
    
    (ok true)
  )
)

;; Submit an anomaly report
(define-public (submit-anomaly-report 
  (blockchain (string-ascii 20))
  (report-type (string-ascii 50))
  (severity uint))
  (let
    (
      (sender tx-sender)
      (current-nonce (var-get report-nonce))
      (node-info (unwrap! (map-get? monitoring-nodes sender) err-node-not-found))
    )
    (asserts! (get active node-info) err-not-authorized)
    (asserts! (<= severity u10) err-invalid-amount)
    
    ;; Create anomaly report
    (map-set anomaly-reports current-nonce {
      reporter: sender,
      blockchain: blockchain,
      report-type: report-type,
      severity: severity,
      timestamp: block-height,
      verified: false,
      reward-claimed: false
    })
    
    ;; Update node stats
    (map-set monitoring-nodes sender 
      (merge node-info {
        total-reports: (+ (get total-reports node-info) u1),
        last-activity: block-height
      })
    )
    
    (var-set report-nonce (+ current-nonce u1))
    (ok current-nonce)
  )
)

;; Verify an anomaly report (owner only)
(define-public (verify-report (report-id uint) (is-accurate bool))
  (let
    (
      (report (unwrap! (map-get? anomaly-reports report-id) err-node-not-found))
      (reporter (get reporter report))
      (node-info (unwrap! (map-get? monitoring-nodes reporter) err-node-not-found))
      (reward-amount (* (get severity report) u1000000))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (get verified report)) err-already-claimed)
    
    ;; Mark report as verified
    (map-set anomaly-reports report-id
      (merge report { verified: true })
    )
    
    ;; Award rewards if accurate
    (if is-accurate
      (let
        (
          (rewards (default-to 
            { total-earned: u0, pending-rewards: u0, last-claim-height: u0 }
            (map-get? node-rewards reporter)
          ))
        )
        (map-set node-rewards reporter {
          total-earned: (get total-earned rewards),
          pending-rewards: (+ (get pending-rewards rewards) reward-amount),
          last-claim-height: (get last-claim-height rewards)
        })
        (ok true)
      )
      (ok true)
    )
  )
)

;; Claim pending rewards
(define-public (claim-rewards)
  (let
    (
      (sender tx-sender)
      (rewards (unwrap! (map-get? node-rewards sender) err-node-not-found))
      (pending (get pending-rewards rewards))
    )
    (asserts! (> pending u0) err-insufficient-balance)
    
    ;; Update rewards record
    (map-set node-rewards sender {
      total-earned: (+ (get total-earned rewards) pending),
      pending-rewards: u0,
      last-claim-height: block-height
    })
    
    ;; In production, this would transfer tokens to the sender
    (ok pending)
  )
)

;; Add stake to existing node
(define-public (add-stake (additional-amount uint))
  (let
    (
      (sender tx-sender)
      (node-info (unwrap! (map-get? monitoring-nodes sender) err-node-not-found))
    )
    (asserts! (> additional-amount u0) err-invalid-amount)
    
    (map-set monitoring-nodes sender
      (merge node-info {
        staked-amount: (+ (get staked-amount node-info) additional-amount)
      })
    )
    
    (var-set total-staked (+ (var-get total-staked) additional-amount))
    (ok true)
  )
)

;; Deactivate node (keep stake locked)
(define-public (deactivate-node)
  (let
    (
      (sender tx-sender)
      (node-info (unwrap! (map-get? monitoring-nodes sender) err-node-not-found))
    )
    (map-set monitoring-nodes sender
      (merge node-info { active: false })
    )
    (ok true)
  )
)

;; Reactivate node
(define-public (reactivate-node)
  (let
    (
      (sender tx-sender)
      (node-info (unwrap! (map-get? monitoring-nodes sender) err-node-not-found))
    )
    (map-set monitoring-nodes sender
      (merge node-info { 
        active: true,
        last-activity: block-height
      })
    )
    (ok true)
  )
)

;; Fund reward pool (owner only)
(define-public (fund-reward-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    
    (var-set reward-pool (+ (var-get reward-pool) amount))
    (ok true)
  )
)