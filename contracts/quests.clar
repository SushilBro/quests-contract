(use-trait token 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_INVALID_QUEST (err u1002))
(define-constant ERR_QUEST_NOT_ACTIVE (err u1003))
(define-constant ERR_ALREADY_PARTICIPATING (err u1004))
(define-constant ERR_NOT_PARTICIPATING (err u1005))
(define-constant ERR_ACTIVITY_ALREADY_COMPLETED (err u1006))
(define-constant ERR_WRONG_TOKEN (err u1007)) ;; use it today
(define-constant ERR_INVALID_ID (err u1008))
(define-constant ERR_AMOUNT_NOT_LOCKED (err u1009))
(define-constant ERR_INVALID_COMMITMENT_AMOUNT (err u1014))

;; Quest status codes
(define-constant QUEST_ACTIVE u1)
(define-constant QUEST_CANCELLED u2)


;; Constants
(define-constant ACTIVITIES_PER_QUEST u3)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var quest-counter uint u0)

(define-map quests
  (string-ascii 36)
  {
    creator: principal,
    title: (string-ascii 200),
    status: uint,
    created-time: uint,
    participant-count: uint,
    token-used: principal,
    commitment-amount: uint
  }
)

(define-map participants
  { quest-id: (string-ascii 36), participant: principal }
  {
    joined-block: uint,
    activities-completed: uint,
    amount-locked: bool,
    locked-amount: uint
  }
)

;; Public functions
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
      commitment-amount: commitment-amount
    }))
      (asserts! (is-eq (len quest-id) u36) ERR_INVALID_ID)
      (asserts! (> commitment-amount u0) ERR_INVALID_COMMITMENT_AMOUNT)
      (asserts! (is-none (map-get? quests quest-id)) ERR_INVALID_QUEST)
      (asserts! (is-token-enabled (contract-of use-token)) ERR_WRONG_TOKEN)
      (try! (restrict-assets? tx-sender 
        ((with-ft (contract-of use-token) "*" commitment-amount) (with-stx commitment-amount))
        (try! (contract-call? .treasury deposit commitment-amount tx-sender use-token))
      ))
      (asserts! (map-insert quests quest-id quest-data) ERR_INVALID_QUEST)
      (ok (var-set quest-counter (+ current-count u1)))
  )
)

;; #[allow(unchecked_data)]
(define-public (join-quest (quest-id (string-ascii 36)) (participation-amount uint) (use-token <token>))
  (let (
    (quest (unwrap! (map-get? quests quest-id) ERR_INVALID_QUEST))
    (participant-key { quest-id: quest-id, participant: tx-sender })
  )
      (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
      (asserts! (is-token-enabled (contract-of use-token)) ERR_WRONG_TOKEN)
      (asserts! (is-eq (get status quest) QUEST_ACTIVE) ERR_QUEST_NOT_ACTIVE)
      (asserts! (is-none (map-get? participants participant-key)) ERR_ALREADY_PARTICIPATING)
      (try! (restrict-assets? tx-sender
        ((with-ft (contract-of use-token) "*" participation-amount) (with-stx participation-amount))
        (try! (contract-call? use-token transfer participation-amount tx-sender current-contract none))
      ))
      (asserts! (map-insert participants participant-key {
        joined-block: burn-block-height,
        activities-completed: u0,
        amount-locked: true,
        locked-amount: participation-amount
      }) ERR_INVALID_QUEST)
      (ok (map-set quests quest-id (merge quest { participant-count: (+ (get participant-count quest) u1) })))
  )
)
;; #[allow(unchecked_data)]
(define-public (complete-activity (quest-id (string-ascii 36)) (use-token <token>))
  (let (
    (quest (unwrap! (map-get? quests quest-id) ERR_INVALID_QUEST))
    (participant-key { quest-id: quest-id, participant: tx-sender })
    (participant (unwrap! (map-get? participants participant-key) ERR_NOT_PARTICIPATING))
    (completed-count (get activities-completed participant))
    (new-count (+ completed-count u1))
    (is-completed (is-eq new-count ACTIVITIES_PER_QUEST))
  )
      (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status quest) QUEST_ACTIVE) ERR_QUEST_NOT_ACTIVE)
      (asserts! (< completed-count ACTIVITIES_PER_QUEST) ERR_ACTIVITY_ALREADY_COMPLETED)
      (asserts! (get amount-locked participant) ERR_AMOUNT_NOT_LOCKED)
      ;; Auto-refund when all activities are completed
      (if is-completed
        (begin
          ;; Refund locked STX to participant
          (asserts! (is-eq (contract-of use-token) (get token-used quest)) ERR_WRONG_TOKEN)
          (try! (as-contract? ((with-ft (contract-of use-token) "*" (get locked-amount participant)) (with-stx (get locked-amount participant)))
            (begin
              (try! (restrict-assets? tx-sender
                ((with-ft (contract-of use-token) "*" (get locked-amount participant)) (with-stx (get locked-amount participant)))
                (try! (contract-call? use-token transfer (get locked-amount participant) tx-sender (get participant participant-key) none))
              ))
              true
            )
          ))
          ;; Update participant: mark activities as complete and unlock amount
          (ok (map-set participants participant-key (merge participant { 
            activities-completed: new-count,
            amount-locked: false
          })))
        )
        ;; Update only activity counter (not yet complete)
        (ok (map-set participants participant-key (merge participant { activities-completed: new-count })))
      )
  )
)

;; Cancel quest and refund participants (only creator)
;; #[allow(unchecked_data)]
(define-public (cancel-quest (quest-id (string-ascii 36)) (use-token <token>))
  (let (
    (quest (unwrap! (map-get? quests quest-id) ERR_INVALID_QUEST))
  )
      (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
      (asserts! (is-eq tx-sender (get creator quest)) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status quest) QUEST_ACTIVE) ERR_QUEST_NOT_ACTIVE)
      (asserts! (is-eq (get token-used quest) (contract-of use-token)) ERR_WRONG_TOKEN)
      (try! (restrict-assets? tx-sender
        ((with-ft (contract-of use-token) "*" u0))
        (try! (contract-call? .treasury withdraw (get commitment-amount quest) tx-sender use-token))
      ))
      (ok (map-set quests quest-id (merge quest { status: QUEST_CANCELLED })))
  )
)

(define-public (refund-participant (quest-id (string-ascii 36)) (use-token <token>))
  (let (
    (quest (unwrap! (map-get? quests quest-id) ERR_INVALID_QUEST))
    (participant-key { quest-id: quest-id, participant: tx-sender })
    (participant (unwrap! (map-get? participants participant-key) ERR_NOT_PARTICIPATING))
  )
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq (contract-of use-token) (get token-used quest)) ERR_WRONG_TOKEN)
    (asserts! (get amount-locked participant) ERR_AMOUNT_NOT_LOCKED)
    (try! (as-contract? ((with-ft (contract-of use-token) "*" (get locked-amount participant)) (with-stx (get locked-amount participant)))
      (begin
        (try! (restrict-assets? tx-sender
          ((with-ft (contract-of use-token) "*" (get locked-amount participant)) (with-stx (get locked-amount participant)))
          (try! (contract-call? use-token transfer (get locked-amount participant)  tx-sender (get participant participant-key) none))
        ))
        true
      )
    ))
    (ok (map-set participants participant-key (merge participant { amount-locked: false })))
  )
)

;; #[allow(unchecked_data)]
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq contract-caller (var-get contract-owner)) ERR_UNAUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)


;; Get quest details
(define-read-only (get-quest (quest-id (string-ascii 36)))
  (map-get? quests quest-id)
)


;; Get participant status
(define-read-only (get-participant-status (quest-id (string-ascii 36)) (participant principal))
  (map-get? participants { quest-id: quest-id, participant: participant })
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Get quest counter
(define-read-only (get-quest-counter)
  (var-get quest-counter)
)

;; Check if participant has completed all three activities of a quest
;; Optimized: single counter check instead of 3 field checks
(define-read-only (check-quest-completion-status (quest-id (string-ascii 36)) (participant principal))
  (match (map-get? participants { quest-id: quest-id, participant: participant })
    participant-info (is-eq (get activities-completed participant-info) ACTIVITIES_PER_QUEST)
    false
  )
)

;; Private functions

(define-private (is-token-enabled (token-id principal))
  (contract-call? 'SP2GW18TVQR75W1VT53HYGBRGKFRV5BFYNAF5SS5J.ZADAO-token-whitelist-v1 is-token-enabled token-id)
)

;; SP2GW18TVQR75W1VT53HYGBRGKFRV5BFYNAF5SS5J.ZADAO-token-whitelist-v2
;; SP2GW18TVQR75W1VT53HYGBRGKFRV5BFYNAF5SS5J.ZADAO-token-whitelist-v1