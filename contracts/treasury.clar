(use-trait token 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; title: treasury
;; version: 1.0.0
;; summary: Treasury contract to receive and hold tokens from quest system
;; description: A treasury contract that receives tokens from the quest system and holds them securely. Only the contract owner can withdraw funds.

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u2001))
(define-constant ERR_INSUFFICIENT_BALANCE (err u2002))
(define-constant ERR_INVALID_AMOUNT (err u2003))
(define-constant ERR_WRONG_TOKEN (err u2004))
(define-constant ERR_TRANSFER_INDEX_PREFIX u1000)

;; Data variables
(define-data-var treasury-owner principal tx-sender)

;; Map to track balances for each token contract
;; Key: token contract principal, Value: balance amount
(define-map token-balances
  principal
  uint
)

;; Public functions

;; Deposit tokens to treasury
;; Anyone can deposit tokens to the treasury
;; #[allow(unchecked_data)]
(define-public (deposit
    (amount uint)
    (sender principal)
    (token-contract <token>)
  )
  (let ((current-balance (default-to u0 (map-get? token-balances (contract-of token-contract)))))
    (asserts! (is-token-enabled (contract-of token-contract)) ERR_WRONG_TOKEN)
    (try! (restrict-assets? sender
      ((with-ft (contract-of token-contract) "*" amount) (with-stx amount))
      (try! (contract-call? token-contract transfer amount sender current-contract
        none
      ))
    ))
    (ok (map-set token-balances (contract-of token-contract)
      (+ current-balance amount)
    ))
  )
)

;; Withdraw tokens from treasury (only quest creator)
;; #[allow(unchecked_data)]
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
    ;; Transfer tokens from contract to recipient with asset restriction
    (try! (as-contract? ((with-ft token-principal "*" amount) (with-stx amount))
        (try! (contract-call? token-contract transfer amount tx-sender recipient none))
    ))
    ;; Update balance
    (ok (map-set token-balances token-principal (- current-balance amount)))
  )
)

;; Set treasury owner (only current owner)
;; #[allow(unchecked_data)]
(define-public (set-treasury-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (var-get treasury-owner)) ERR_UNAUTHORIZED)
    (ok (var-set treasury-owner new-owner))
  )
)

;; Helper function to transfer tokens to a single winner
;; Accumulator: (response {index: uint, token-contract: <token>, amount: uint} uint)
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
        )
      ))
      (ok {
        index: (+ index u1),
        token-contract: token-contract,
        amount: amount,
      })
    )
    err-index (err err-index)
  )
)

;; Helper function to process all winners for a single token
;; Accumulator: (response {token-index: uint, winners: (list 100 principal)} uint)
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
        (fee (/ balance u2)) ;; 50% of the balance for the platform fee
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
              ;; Update balance after all transfers
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

;; Read-only functions

;; Get balance for a specific token
(define-read-only (get-balance (token-principal principal))
  (default-to u0 (map-get? token-balances token-principal))
)

;; Get treasury owner
(define-read-only (get-treasury-owner)
  (var-get treasury-owner)
)

(define-private (is-token-enabled (token-id principal))
  (contract-call?
    'SP2GW18TVQR75W1VT53HYGBRGKFRV5BFYNAF5SS5J.ZADAO-token-whitelist-v2
    is-token-enabled token-id
  )
)
