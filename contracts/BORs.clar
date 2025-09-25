;; Bitcoin Ordinal Rental System
;; A smart contract for renting Bitcoin Ordinals/NFTs with collateral-based security

;; Constants
(define-constant contract-owner tx-sender)
(define-constant platform-fee-rate u250) ;; 2.5% platform fee (250/10000)
(define-constant min-rental-duration u144) ;; Minimum 1 day (144 blocks 24 hours)
(define-constant max-rental-duration u14400) ;; Maximum 100 days

;; Error codes
(define-constant err-not-authorized (err u100))
(define-constant err-listing-not-found (err u101))
(define-constant err-already-rented (err u102))
(define-constant err-insufficient-payment (err u103))
(define-constant err-invalid-duration (err u104))
(define-constant err-rental-not-active (err u105))
(define-constant err-rental-not-expired (err u106))
(define-constant err-already-returned (err u107))
(define-constant err-invalid-collateral (err u108))

;; Data structures
(define-map rental-listings
  { ordinal-id: uint }
  {
    owner: principal,
    rental-fee: uint,
    collateral-required: uint,
    max-duration: uint,
    is-active: bool,
    created-at: uint
  }
)

(define-map active-rentals
  { ordinal-id: uint }
  {
    renter: principal,
    owner: principal,
    rental-fee: uint,
    collateral-paid: uint,
    rental-start: uint,
    rental-end: uint,
    is-returned: bool
  }
)

(define-map user-stats
  { user: principal }
  {
    rentals-completed: uint,
    rentals-defaulted: uint,
    total-earned: uint,
    reputation-score: uint
  }
)

;; Platform fee tracking
(define-data-var total-platform-fees uint u0)
(define-data-var total-rentals-created uint u0)

;; Platform management
(define-data-var platform-fee-recipient principal contract-owner)
(define-data-var emergency-pause bool false)

;; Helper functions
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount platform-fee-rate) u10000)
)

(define-private (update-user-reputation (user principal) (completed bool))
  (let ((current-stats (default-to 
                         { rentals-completed: u0, rentals-defaulted: u0, total-earned: u0, reputation-score: u100 }
                         (map-get? user-stats { user: user }))))
    (if completed
      (map-set user-stats { user: user }
        (merge current-stats {
          rentals-completed: (+ (get rentals-completed current-stats) u1),
          reputation-score: (if (> (+ (get reputation-score current-stats) u10) u1000) u1000 (+ (get reputation-score current-stats) u10))
        }))
      (map-set user-stats { user: user }
        (merge current-stats {
          rentals-defaulted: (+ (get rentals-defaulted current-stats) u1),
          reputation-score: (if (>= (get reputation-score current-stats) u50)
                             (- (get reputation-score current-stats) u50)
                             u0)
        }))))
)

;; Main functions

;; 1. List an ordinal for rent
(define-public (list-ordinal-for-rent (ordinal-id uint) (rental-fee uint) (collateral-required uint) (max-duration uint))
  (begin
    (asserts! (not (var-get emergency-pause)) err-not-authorized)
    (asserts! (and (>= max-duration min-rental-duration) (<= max-duration max-rental-duration)) err-invalid-duration)
    (asserts! (> collateral-required rental-fee) err-invalid-collateral)
    (asserts! (is-none (map-get? rental-listings { ordinal-id: ordinal-id })) err-already-rented)
    
    ;; Create the listing
    (map-set rental-listings { ordinal-id: ordinal-id }
      {
        owner: tx-sender,
        rental-fee: rental-fee,
        collateral-required: collateral-required,
        max-duration: max-duration,
        is-active: true,
        created-at: stacks-block-height
      })
    
    (print {
      event: "ordinal-listed",
      ordinal-id: ordinal-id,
      owner: tx-sender,
      rental-fee: rental-fee,
      collateral-required: collateral-required
    })
    
    (ok ordinal-id)
  )
)

;; 2. Rent an ordinal
(define-public (rent-ordinal (ordinal-id uint) (rental-duration uint))
  (let ((listing (unwrap! (map-get? rental-listings { ordinal-id: ordinal-id }) err-listing-not-found))
        (rental-fee (get rental-fee (unwrap! (map-get? rental-listings { ordinal-id: ordinal-id }) err-listing-not-found)))
        (collateral-required (get collateral-required (unwrap! (map-get? rental-listings { ordinal-id: ordinal-id }) err-listing-not-found)))
        (total-payment (+ rental-fee collateral-required))
        (platform-fee (calculate-platform-fee rental-fee))
        (owner-payment (- rental-fee platform-fee)))
    
    (asserts! (not (var-get emergency-pause)) err-not-authorized)
    (asserts! (get is-active listing) err-already-rented)
    (asserts! (and (>= rental-duration min-rental-duration) (<= rental-duration (get max-duration listing))) err-invalid-duration)
    (asserts! (is-none (map-get? active-rentals { ordinal-id: ordinal-id })) err-already-rented)
    
    ;; Transfer payment from renter to contract
    (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
    
    ;; Pay the owner (minus platform fee)
    (try! (as-contract (stx-transfer? owner-payment tx-sender (get owner listing))))
    
    ;; Update platform fees
    (var-set total-platform-fees (+ (var-get total-platform-fees) platform-fee))
    
    ;; Create rental record
    (map-set active-rentals { ordinal-id: ordinal-id }
      {
        renter: tx-sender,
        owner: (get owner listing),
        rental-fee: rental-fee,
        collateral-paid: collateral-required,
        rental-start: stacks-block-height,
        rental-end: (+ stacks-block-height rental-duration),
        is-returned: false
      })
    
    ;; Mark listing as inactive
    (map-set rental-listings { ordinal-id: ordinal-id }
      (merge listing { is-active: false }))
    
    ;; Update stats
    (var-set total-rentals-created (+ (var-get total-rentals-created) u1))
    
    (print {
      event: "ordinal-rented",
      ordinal-id: ordinal-id,
      renter: tx-sender,
      owner: (get owner listing),
      rental-end: (+ stacks-block-height rental-duration)
    })
    
    (ok ordinal-id)
  )
)

;; 3. Return ordinal (can be called by renter or after expiration by anyone)
(define-public (return-ordinal (ordinal-id uint))
  (let ((rental (unwrap! (map-get? active-rentals { ordinal-id: ordinal-id }) err-rental-not-active)))
    
    (asserts! (not (get is-returned rental)) err-already-returned)
    (asserts! 
      (or 
        (is-eq tx-sender (get renter rental)) ;; Renter can return anytime
        (>= stacks-block-height (get rental-end rental))) ;; Anyone can return after expiration
      err-not-authorized)
    
    (let ((is-on-time (<= stacks-block-height (get rental-end rental)))
          (collateral-amount (get collateral-paid rental))
          (renter-address (get renter rental))
          (owner-address (get owner rental)))
      
      ;; Return collateral to renter if returned on time, otherwise to owner
      (if is-on-time
        (try! (as-contract (stx-transfer? collateral-amount tx-sender renter-address)))
        (try! (as-contract (stx-transfer? collateral-amount tx-sender owner-address))))
      
      ;; Mark as returned
      (map-set active-rentals { ordinal-id: ordinal-id }
        (merge rental { is-returned: true }))
      
      ;; Reactivate listing if it exists
      (match (map-get? rental-listings { ordinal-id: ordinal-id })
        listing (map-set rental-listings { ordinal-id: ordinal-id }
                  (merge listing { is-active: true }))
        true)
      
      ;; Update reputation
      (update-user-reputation renter-address is-on-time)
      
      (print {
        event: "ordinal-returned",
        ordinal-id: ordinal-id,
        renter: renter-address,
        on-time: is-on-time
      })
      
      (ok is-on-time)
    )
  )
)

;; 4. Cancel listing (owner only)
(define-public (cancel-listing (ordinal-id uint))
  (let ((listing (unwrap! (map-get? rental-listings { ordinal-id: ordinal-id }) err-listing-not-found)))
    
    (asserts! (is-eq tx-sender (get owner listing)) err-not-authorized)
    (asserts! (is-none (map-get? active-rentals { ordinal-id: ordinal-id })) err-already-rented)
    
    (map-delete rental-listings { ordinal-id: ordinal-id })
    
    (print {
      event: "listing-cancelled",
      ordinal-id: ordinal-id,
      owner: tx-sender
    })
    
    (ok ordinal-id)
  )
)

;; 5. Extend rental (renter pays additional fee)
(define-public (extend-rental (ordinal-id uint) (additional-duration uint))
  (let ((rental (unwrap! (map-get? active-rentals { ordinal-id: ordinal-id }) err-rental-not-active))
        (listing (unwrap! (map-get? rental-listings { ordinal-id: ordinal-id }) err-listing-not-found)))
    
    (asserts! (is-eq tx-sender (get renter rental)) err-not-authorized)
    (asserts! (not (get is-returned rental)) err-already-returned)
    (asserts! (< stacks-block-height (get rental-end rental)) err-rental-not-expired)
    
    (let ((base-rental-fee (get rental-fee rental))
          (original-duration (- (get rental-end rental) (get rental-start rental)))
          (additional-fee (/ (* base-rental-fee additional-duration) original-duration))
          (platform-fee (calculate-platform-fee additional-fee))
          (owner-payment (- additional-fee platform-fee))
          (owner-address (get owner rental)))
      
      ;; Pay additional rental fee
      (try! (stx-transfer? additional-fee tx-sender (as-contract tx-sender)))
      (try! (as-contract (stx-transfer? owner-payment tx-sender owner-address)))
      
      ;; Update platform fees
      (var-set total-platform-fees (+ (var-get total-platform-fees) platform-fee))
      
      ;; Update rental end time
      (map-set active-rentals { ordinal-id: ordinal-id }
        (merge rental { rental-end: (+ (get rental-end rental) additional-duration) }))
      
      (print {
        event: "rental-extended",
        ordinal-id: ordinal-id,
        renter: tx-sender,
        new-end: (+ (get rental-end rental) additional-duration)
      })
      
      (ok additional-fee)
    )
  )
)

;; Read-only functions

(define-read-only (get-listing (ordinal-id uint))
  (map-get? rental-listings { ordinal-id: ordinal-id })
)

(define-read-only (get-active-rental (ordinal-id uint))
  (map-get? active-rentals { ordinal-id: ordinal-id })
)

(define-read-only (get-user-stats (user principal))
  (default-to 
    { rentals-completed: u0, rentals-defaulted: u0, total-earned: u0, reputation-score: u100 }
    (map-get? user-stats { user: user }))
)

(define-read-only (get-platform-stats)
  {
    total-platform-fees: (var-get total-platform-fees),
    total-rentals-created: (var-get total-rentals-created),
    fee-recipient: (var-get platform-fee-recipient)
  }
)

(define-read-only (is-rental-expired (ordinal-id uint))
  (match (map-get? active-rentals { ordinal-id: ordinal-id })
    rental (>= stacks-block-height (get rental-end rental))
    false)
)

;; Admin functions (contract owner only)

(define-public (set-fee-recipient (new-recipient principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (var-set platform-fee-recipient new-recipient)
    (ok true)
  )
)

(define-public (withdraw-platform-fees)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (let ((fees (var-get total-platform-fees)))
      (var-set total-platform-fees u0)
      (try! (as-contract (stx-transfer? fees tx-sender (var-get platform-fee-recipient))))
      (ok fees)
    )
  )
)

(define-public (emergency-pause-toggle)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (var-set emergency-pause (not (var-get emergency-pause)))
    (ok (var-get emergency-pause))
  )
)
