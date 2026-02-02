;; =============================================================================
;; TREASURY CONTRACT
;; =============================================================================
;; Holds tokens deposited by the quests contract (creator commitments) and
;; supports withdrawals by quest creators and reward distribution to random
;; winners. Token balances are tracked per token contract.
;; =============================================================================

(use-trait token 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; =============================================================================
;; ERROR CODES
;; =============================================================================

(define-constant ERR_UNAUTHORIZED (err u2001))
(define-constant ERR_WRONG_TOKEN (err u2002))
;; Base index for transfer errors when rewarding winners (err = base + token index).
(define-constant ERR_TRANSFER_INDEX_PREFIX u1000)

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var treasury-owner principal tx-sender)

;; =============================================================================
;; MAPS
;; =============================================================================

;; token contract principal -> balance (uints)
(define-map token-balances
  principal
  uint
)

;; =============================================================================
;; PUBLIC FUNCTIONS - Deposits and withdrawals
;; =============================================================================

;; Deposit tokens into the treasury. Anyone can deposit; typically called
;; by the quests contract when a creator creates a quest.

(define-public (deposit
    (amount uint)
    (sender principal)
    (token-contract <token>)
  )
  (let ((current-balance (default-to u0 (map-get? token-balances (contract-of token-contract)))))
    (asserts! (is-token-enabled (contract-of token-contract)) ERR_WRONG_TOKEN)
    (try! (restrict-assets? sender (
        (with-ft (contract-of token-contract) "*" amount)
        (with-stx amount)
      )
      (try! (contract-call? token-contract transfer amount sender current-contract none))
    ))
    (ok (map-set token-balances (contract-of token-contract)
      (+ current-balance amount)
    ))
  )
)

;; Withdraw tokens from the treasury. Only the quests contract can call
;; (e.g. when a quest creator cancels a quest).

(define-public (withdraw
    (amount uint)
    (recipient principal)
    (token-contract <token>)
  )
  (let (
      (token-principal (contract-of token-contract))
      (current-balance (default-to u0 (map-get? token-balances token-principal)))
    )
    (asserts! (is-eq contract-caller .quests) ERR_UNAUTHORIZED)
    (asserts! (is-token-enabled token-principal) ERR_WRONG_TOKEN)
    (try! (as-contract? ((with-ft token-principal "*" amount) (with-stx amount))
      (try! (contract-call? token-contract transfer amount tx-sender recipient none))
    ))
    (ok (map-set token-balances token-principal (- current-balance amount)))
  )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - Admin
;; =============================================================================

;; Set the treasury owner. Only the current owner can call.

(define-public (set-treasury-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (var-get treasury-owner)) ERR_UNAUTHORIZED)
    (ok (var-set treasury-owner new-owner))
  )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - Rewards
;; =============================================================================

;; Distribute rewards to a list of winners across multiple tokens.
;; Only treasury owner can call. For each token, 50% of balance is split
;; among winners; the rest remains as platform balance.

(define-public (reward-random-winners
    (winners (list 100 principal))
    (tokens (list 100 <token>))
  )
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (var-get treasury-owner)) ERR_UNAUTHORIZED)
    (match (fold process-token-winners tokens
      (ok {
        token-index: u0,
        winners: winners,
      })
    )
      result (ok true)
      err-result (err err-result)
    )
  )
)

;; =============================================================================
;; PRIVATE HELPERS - Reward distribution
;; =============================================================================

;; Transfers tokens to a single winner. Used as fold step; accumulator
;; is (response { index, token-contract, amount } uint).
(define-private (transfer-to-winner
    (winner principal)
    (result (response {
      index: uint,
      token-contract: <token>,
      amount: uint,
    }
      uint
    ))
  )
  (match result
    acc (let (
        (token-contract (get token-contract acc))
        (amount (get amount acc))
        (index (get index acc))
        (token-principal (contract-of token-contract))
      )
      (asserts! (is-token-enabled token-principal) ERR_WRONG_TOKEN)
      (try! (as-contract? ((with-ft token-principal "*" amount) (with-stx amount))
        (begin
          (unwrap!
            (contract-call? token-contract transfer amount tx-sender winner none)
            (err (+ ERR_TRANSFER_INDEX_PREFIX index))
          )
          true
        )))
      (ok {
        index: (+ index u1),
        token-contract: token-contract,
        amount: amount,
      })
    )
    err-index (err err-index)
  )
)

;; Processes all winners for one token: splits 50% of token balance among
;; winners. Accumulator: (response { token-index, winners } uint).
(define-private (process-token-winners
    (token-contract <token>)
    (result (response {
      token-index: uint,
      winners: (list 100 principal),
    }
      uint
    ))
  )
  (match result
    acc (let (
        (token-principal (contract-of token-contract))
        (balance (default-to u0 (map-get? token-balances token-principal)))
        (fee (/ balance u2))
        (winners (get winners acc))
        (winners-count (len winners))
        (token-index (get token-index acc))
      )
      (if (is-eq winners-count u0)
        (ok {
          token-index: (+ token-index u1),
          winners: winners,
        })
        (let ((amount-per-winner (/ fee winners-count)))
          (match (fold transfer-to-winner winners
            (ok {
              index: u0,
              token-contract: token-contract,
              amount: amount-per-winner,
            })
          )
            transfer-result (begin
              (try! (as-contract? ((with-ft token-principal "*" fee) (with-stx fee))
                (try! (contract-call? token-contract transfer fee tx-sender
                  (var-get treasury-owner) none
                ))
              ))
              (map-set token-balances token-principal (- balance balance))
              (ok {
                token-index: (+ token-index u1),
                winners: winners,
              })
            )
            err-transfer (err err-transfer)
          )
        )
      )
    )
    err-index (err err-index)
  )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-balance (token-principal principal))
  (default-to u0 (map-get? token-balances token-principal))
)

(define-read-only (get-treasury-owner)
  (var-get treasury-owner)
)

;; =============================================================================
;; PRIVATE HELPERS - Token validation
;; =============================================================================

;; Checks token against whitelist (ZADAO-token-whitelist-v2).
(define-private (is-token-enabled (token-id principal))
  (contract-call?
    'SP2GW18TVQR75W1VT53HYGBRGKFRV5BFYNAF5SS5J.ZADAO-token-whitelist-v2
    is-token-enabled token-id
  )
)
