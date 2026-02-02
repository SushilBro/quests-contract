;; =============================================================================
;; QUESTS CONTRACT
;; =============================================================================
;; Manages quest creation, participation, activity completion, and refunds.
;; Integrates with treasury for creator commitment and token whitelist for
;; allowed tokens. Participants lock tokens and complete activities to earn
;; refunds.
;; =============================================================================

(use-trait token 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; =============================================================================
;; ERROR CODES
;; =============================================================================

(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_INVALID_QUEST (err u1002))
(define-constant ERR_QUEST_NOT_ACTIVE (err u1003))
(define-constant ERR_ALREADY_PARTICIPATING (err u1004))
(define-constant ERR_NOT_PARTICIPATING (err u1005))
(define-constant ERR_ACTIVITY_ALREADY_COMPLETED (err u1006))
(define-constant ERR_WRONG_TOKEN (err u1007))
(define-constant ERR_INVALID_ID (err u1008))
(define-constant ERR_AMOUNT_NOT_LOCKED (err u1009))
(define-constant ERR_INVALID_COMMITMENT_AMOUNT (err u1014))

;; =============================================================================
;; QUEST STATUS CODES
;; =============================================================================

(define-constant QUEST_ACTIVE u1)
(define-constant QUEST_CANCELLED u2)

;; =============================================================================
;; CONSTANTS
;; =============================================================================

;; Number of activities a participant must complete per quest to get refund.
(define-constant ACTIVITIES_PER_QUEST u3)

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var contract-owner principal tx-sender)
(define-data-var quest-counter uint u0)

;; =============================================================================
;; MAPS
;; =============================================================================

;; quest-id (UUID string) -> quest metadata
(define-map quests
  (string-ascii 36)
  {
    creator: principal,
    title: (string-ascii 200),
    status: uint,
    created-time: uint,
    participant-count: uint,
    token-used: principal,
    commitment-amount: uint,
  }
)

;; (quest-id, participant) -> participation record
(define-map participants
  {
    quest-id: (string-ascii 36),
    participant: principal,
  }
  {
    joined-block: uint,
    activities-completed: uint,
    amount-locked: bool,
    locked-amount: uint,
  }
)

;; =============================================================================
;; PUBLIC FUNCTIONS - Quest lifecycle
;; =============================================================================

;; Create a new quest. Creator locks commitment-amount in treasury.
;; Quest ID must be a 36-character string (e.g. UUID).
;; #[allow(unchecked_data)]
(define-public (create-quest
    (quest-id (string-ascii 36))
    (title (string-ascii 200))
    (use-token <token>)
    (commitment-amount uint)
  )
  (let (
      (current-count (var-get quest-counter))
      (quest-data {
        creator: tx-sender,
        title: title,
        status: QUEST_ACTIVE,
        created-time: stacks-block-time,
        token-used: (contract-of use-token),
        participant-count: u0,
        commitment-amount: commitment-amount,
      })
    )
    (asserts! (is-eq (len quest-id) u36) ERR_INVALID_ID)
    (asserts! (> commitment-amount u0) ERR_INVALID_COMMITMENT_AMOUNT)
    (asserts! (is-none (map-get? quests quest-id)) ERR_INVALID_QUEST)
    (asserts! (is-token-enabled (contract-of use-token)) ERR_WRONG_TOKEN)
    (try! (restrict-assets? tx-sender (
        (with-ft (contract-of use-token) "*" commitment-amount)
        (with-stx commitment-amount)
      )
      (try! (contract-call? .treasury deposit commitment-amount tx-sender use-token))
    ))
    (asserts! (map-insert quests quest-id quest-data) ERR_INVALID_QUEST)
    (ok (var-set quest-counter (+ current-count u1)))
  )
)

;; Join a quest by locking participation-amount. Only contract-caller can join.
;; #[allow(unchecked_data)]
(define-public (join-quest
    (quest-id (string-ascii 36))
    (participation-amount uint)
    (use-token <token>)
  )
  (let (
      (quest (unwrap! (map-get? quests quest-id) ERR_INVALID_QUEST))
      (participant-key {
        quest-id: quest-id,
        participant: tx-sender,
      })
    )
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-token-enabled (contract-of use-token)) ERR_WRONG_TOKEN)
    (asserts! (is-eq (get status quest) QUEST_ACTIVE) ERR_QUEST_NOT_ACTIVE)
    (asserts! (is-none (map-get? participants participant-key))
      ERR_ALREADY_PARTICIPATING
    )
    (try! (restrict-assets? tx-sender (
        (with-ft (contract-of use-token) "*" participation-amount)
        (with-stx participation-amount)
      )
      (try! (contract-call? use-token transfer participation-amount tx-sender
        current-contract none
      ))
    ))
    (asserts!
      (map-insert participants participant-key {
        joined-block: burn-block-height,
        activities-completed: u0,
        amount-locked: true,
        locked-amount: participation-amount,
      })
      ERR_INVALID_QUEST
    )
    (ok (map-set quests quest-id
      (merge quest { participant-count: (+ (get participant-count quest) u1) })
    ))
  )
)

;; Record one activity completion. When all ACTIVITIES_PER_QUEST are done,
;; participant is auto-refunded their locked amount.
;; #[allow(unchecked_data)]
(define-public (complete-activity
    (quest-id (string-ascii 36))
    (use-token <token>)
  )
  (let (
      (quest (unwrap! (map-get? quests quest-id) ERR_INVALID_QUEST))
      (participant-key {
        quest-id: quest-id,
        participant: tx-sender,
      })
      (participant (unwrap! (map-get? participants participant-key) ERR_NOT_PARTICIPATING))
      (completed-count (get activities-completed participant))
      (new-count (+ completed-count u1))
      (is-completed (is-eq new-count ACTIVITIES_PER_QUEST))
    )
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status quest) QUEST_ACTIVE) ERR_QUEST_NOT_ACTIVE)
    (asserts! (< completed-count ACTIVITIES_PER_QUEST)
      ERR_ACTIVITY_ALREADY_COMPLETED
    )
    (asserts! (get amount-locked participant) ERR_AMOUNT_NOT_LOCKED)
    ;; Auto-refund when all activities are completed
    (if is-completed
      (begin
        ;; Refund locked tokens to participant
        (asserts! (is-eq (contract-of use-token) (get token-used quest))
          ERR_WRONG_TOKEN
        )
        (try! (as-contract?
          ((with-ft (contract-of use-token) "*" (get locked-amount participant)) (with-stx (get locked-amount participant)))
          (begin
            (try! (restrict-assets? tx-sender (
                (with-ft (contract-of use-token) "*"
                  (get locked-amount participant)
                )
                (with-stx (get locked-amount participant))
              )
              (try! (contract-call? use-token transfer (get locked-amount participant)
                tx-sender (get participant participant-key) none
              ))
            ))
            true
          )))
        ;; Mark activities complete and unlock amount
        (ok (map-set participants participant-key
          (merge participant {
            activities-completed: new-count,
            amount-locked: false,
          })
        ))
      )
      ;; Not yet complete: only increment activity counter
      (ok (map-set participants participant-key
        (merge participant { activities-completed: new-count })
      ))
    )
  )
)

;; Cancel a quest (creator only). Creator gets commitment back from treasury.
;; #[allow(unchecked_data)]
(define-public (cancel-quest
    (quest-id (string-ascii 36))
    (use-token <token>)
  )
  (let ((quest (unwrap! (map-get? quests quest-id) ERR_INVALID_QUEST)))
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get creator quest)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status quest) QUEST_ACTIVE) ERR_QUEST_NOT_ACTIVE)
    (asserts! (is-eq (get token-used quest) (contract-of use-token))
      ERR_WRONG_TOKEN
    )
    (try! (restrict-assets? tx-sender (
      )
      (try! (contract-call? .treasury withdraw (get commitment-amount quest) tx-sender
        use-token
      ))
    ))
    (ok (map-set quests quest-id (merge quest { status: QUEST_CANCELLED })))
  )
)

;; Refund a participant's locked amount without completing all activities.
;; Callable by participant when amount is still locked.
(define-public (refund-participant
    (quest-id (string-ascii 36))
    (use-token <token>)
  )
  (let (
      (quest (unwrap! (map-get? quests quest-id) ERR_INVALID_QUEST))
      (participant-key {
        quest-id: quest-id,
        participant: tx-sender,
      })
      (participant (unwrap! (map-get? participants participant-key) ERR_NOT_PARTICIPATING))
    )
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq (contract-of use-token) (get token-used quest))
      ERR_WRONG_TOKEN
    )
    (asserts! (get amount-locked participant) ERR_AMOUNT_NOT_LOCKED)
    (try! (as-contract?
      ((with-ft (contract-of use-token) "*" (get locked-amount participant)) (with-stx (get locked-amount participant)))
      (begin
        (try! (restrict-assets? tx-sender (
            (with-ft (contract-of use-token) "*" (get locked-amount participant))
            (with-stx (get locked-amount participant))
          )
          (try! (contract-call? use-token transfer (get locked-amount participant)
            tx-sender (get participant participant-key) none
          ))
        ))
        true
      )))
    (ok (map-set participants participant-key
      (merge participant { amount-locked: false })
    ))
  )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - Admin
;; =============================================================================

;; Set the contract owner. Only current owner can call.
;; #[allow(unchecked_data)]
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq contract-caller (var-get contract-owner)) ERR_UNAUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-quest (quest-id (string-ascii 36)))
  (map-get? quests quest-id)
)

(define-read-only (get-participant-status
    (quest-id (string-ascii 36))
    (participant principal)
  )
  (map-get? participants {
    quest-id: quest-id,
    participant: participant,
  })
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-quest-counter)
  (var-get quest-counter)
)

;; Returns true if participant has completed all ACTIVITIES_PER_QUEST for this quest.
(define-read-only (check-quest-completion-status
    (quest-id (string-ascii 36))
    (participant principal)
  )
  (match (map-get? participants {
    quest-id: quest-id,
    participant: participant,
  })
    participant-info (is-eq (get activities-completed participant-info) ACTIVITIES_PER_QUEST)
    false
  )
)

;; =============================================================================
;; PRIVATE HELPERS
;; =============================================================================

;; Checks token against whitelist (ZADAO-token-whitelist-v1).
(define-private (is-token-enabled (token-id principal))
  (contract-call?
    'SP2GW18TVQR75W1VT53HYGBRGKFRV5BFYNAF5SS5J.ZADAO-token-whitelist-v1
    is-token-enabled token-id
  )
)

;; Reference: SP2GW18TVQR75W1VT53HYGBRGKFRV5BFYNAF5SS5J.ZADAO-token-whitelist-v2
