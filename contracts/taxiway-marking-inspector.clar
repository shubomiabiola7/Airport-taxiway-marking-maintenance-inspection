;; Taxiway Marking Inspector Contract
;; Manages taxiway marking inspections, maintenance scheduling, and contractor coordination

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-input (err u103))
(define-constant err-already-completed (err u104))
(define-constant err-invalid-status (err u105))
(define-constant err-not-scheduled (err u106))

;; Data Variables
(define-data-var taxiway-nonce uint u0)
(define-data-var inspection-nonce uint u0)
(define-data-var maintenance-nonce uint u0)
(define-data-var contractor-nonce uint u0)

;; Data Maps

;; Taxiway segments registry
(define-map taxiway-segments
  uint
  {
    segment-id: (string-ascii 50),
    name: (string-ascii 100),
    description: (string-ascii 300),
    length-meters: uint,
    current-visibility-score: uint,
    current-condition: (string-ascii 20),
    last-inspection: (optional uint),
    last-maintenance: (optional uint),
    registered-by: principal,
    active: bool
  }
)

(define-map segment-id-to-nonce
  (string-ascii 50)
  uint
)

;; Inspection records
(define-map inspections
  uint
  {
    taxiway-id: uint,
    visibility-score: uint,
    condition-rating: (string-ascii 20),
    notes: (string-ascii 500),
    inspector: principal,
    inspection-date: uint,
    requires-maintenance: bool
  }
)

(define-map taxiway-inspection-history
  { taxiway-id: uint, inspection-index: uint }
  uint
)

(define-map taxiway-inspection-count
  uint
  uint
)

;; Maintenance schedules
(define-map maintenance-schedules
  uint
  {
    taxiway-id: uint,
    scheduled-date: uint,
    work-description: (string-ascii 500),
    priority: (string-ascii 20),
    status: (string-ascii 20),
    contractor-id: (optional uint),
    created-by: principal,
    created-at: uint,
    completed-at: (optional uint),
    completion-notes: (optional (string-ascii 500)),
    post-maintenance-score: (optional uint)
  }
)

(define-map taxiway-maintenance-history
  { taxiway-id: uint, maintenance-index: uint }
  uint
)

(define-map taxiway-maintenance-count
  uint
  uint
)

;; Contractor registry
(define-map contractors
  uint
  {
    name: (string-ascii 100),
    license-number: (string-ascii 50),
    contact-info: (string-ascii 200),
    active: bool,
    total-jobs: uint,
    registered-by: principal
  }
)

(define-map contractor-principals
  principal
  uint
)

;; Read-only functions

(define-read-only (get-taxiway (tw-id uint))
  (map-get? taxiway-segments tw-id)
)

(define-read-only (get-taxiway-by-id (segment-id (string-ascii 50)))
  (match (map-get? segment-id-to-nonce segment-id)
    nonce (map-get? taxiway-segments nonce)
    none
  )
)

(define-read-only (get-inspection (insp-id uint))
  (map-get? inspections insp-id)
)

(define-read-only (get-taxiway-inspection (tw-id uint) (inspection-index uint))
  (match (map-get? taxiway-inspection-history { taxiway-id: tw-id, inspection-index: inspection-index })
    insp-id (map-get? inspections insp-id)
    none
  )
)

(define-read-only (get-taxiway-inspection-count (tw-id uint))
  (default-to u0 (map-get? taxiway-inspection-count tw-id))
)

(define-read-only (get-maintenance-schedule (maint-id uint))
  (map-get? maintenance-schedules maint-id)
)

(define-read-only (get-taxiway-maintenance (tw-id uint) (maintenance-index uint))
  (match (map-get? taxiway-maintenance-history { taxiway-id: tw-id, maintenance-index: maintenance-index })
    maint-id (map-get? maintenance-schedules maint-id)
    none
  )
)

(define-read-only (get-taxiway-maintenance-count (tw-id uint))
  (default-to u0 (map-get? taxiway-maintenance-count tw-id))
)

(define-read-only (get-contractor (contr-id uint))
  (map-get? contractors contr-id)
)

(define-read-only (get-contractor-by-principal (contractor-principal principal))
  (match (map-get? contractor-principals contractor-principal)
    contr-id (map-get? contractors contr-id)
    none
  )
)

(define-read-only (get-current-nonces)
  (ok {
    taxiways: (var-get taxiway-nonce),
    inspections: (var-get inspection-nonce),
    maintenance: (var-get maintenance-nonce),
    contractors: (var-get contractor-nonce)
  })
)

;; Public functions

(define-public (register-taxiway
  (segment-id (string-ascii 50))
  (name (string-ascii 100))
  (description (string-ascii 300))
  (length-meters uint)
)
  (let
    (
      (new-nonce (+ (var-get taxiway-nonce) u1))
    )
    (asserts! (is-none (map-get? segment-id-to-nonce segment-id)) err-invalid-input)
    (asserts! (> (len segment-id) u0) err-invalid-input)
    (asserts! (> (len name) u0) err-invalid-input)
    (asserts! (> length-meters u0) err-invalid-input)
    
    (map-set taxiway-segments new-nonce {
      segment-id: segment-id,
      name: name,
      description: description,
      length-meters: length-meters,
      current-visibility-score: u100,
      current-condition: "excellent",
      last-inspection: none,
      last-maintenance: none,
      registered-by: tx-sender,
      active: true
    })
    
    (map-set segment-id-to-nonce segment-id new-nonce)
    (map-set taxiway-inspection-count new-nonce u0)
    (map-set taxiway-maintenance-count new-nonce u0)
    (var-set taxiway-nonce new-nonce)
    (ok new-nonce)
  )
)

(define-public (record-inspection
  (tw-id uint)
  (visibility-score uint)
  (condition-rating (string-ascii 20))
  (notes (string-ascii 500))
)
  (let
    (
      (new-inspection-id (+ (var-get inspection-nonce) u1))
      (taxiway (unwrap! (map-get? taxiway-segments tw-id) err-not-found))
      (inspection-count (default-to u0 (map-get? taxiway-inspection-count tw-id)))
      (new-inspection-count (+ inspection-count u1))
      (requires-maintenance (< visibility-score u70))
    )
    (asserts! (get active taxiway) err-invalid-status)
    (asserts! (<= visibility-score u100) err-invalid-input)
    (asserts! (> (len condition-rating) u0) err-invalid-input)
    
    (map-set inspections new-inspection-id {
      taxiway-id: tw-id,
      visibility-score: visibility-score,
      condition-rating: condition-rating,
      notes: notes,
      inspector: tx-sender,
      inspection-date: block-height,
      requires-maintenance: requires-maintenance
    })
    
    (map-set taxiway-inspection-history 
      { taxiway-id: tw-id, inspection-index: new-inspection-count }
      new-inspection-id
    )
    
    (map-set taxiway-inspection-count tw-id new-inspection-count)
    
    (map-set taxiway-segments tw-id
      (merge taxiway {
        current-visibility-score: visibility-score,
        current-condition: condition-rating,
        last-inspection: (some block-height)
      })
    )
    
    (var-set inspection-nonce new-inspection-id)
    (ok new-inspection-id)
  )
)

(define-public (schedule-maintenance
  (tw-id uint)
  (scheduled-date uint)
  (work-description (string-ascii 500))
  (priority (string-ascii 20))
)
  (let
    (
      (new-maint-id (+ (var-get maintenance-nonce) u1))
      (taxiway (unwrap! (map-get? taxiway-segments tw-id) err-not-found))
      (maintenance-count (default-to u0 (map-get? taxiway-maintenance-count tw-id)))
      (new-maintenance-count (+ maintenance-count u1))
    )
    (asserts! (get active taxiway) err-invalid-status)
    (asserts! (> (len work-description) u0) err-invalid-input)
    (asserts! (> scheduled-date block-height) err-invalid-input)
    
    (map-set maintenance-schedules new-maint-id {
      taxiway-id: tw-id,
      scheduled-date: scheduled-date,
      work-description: work-description,
      priority: priority,
      status: "scheduled",
      contractor-id: none,
      created-by: tx-sender,
      created-at: block-height,
      completed-at: none,
      completion-notes: none,
      post-maintenance-score: none
    })
    
    (map-set taxiway-maintenance-history
      { taxiway-id: tw-id, maintenance-index: new-maintenance-count }
      new-maint-id
    )
    
    (map-set taxiway-maintenance-count tw-id new-maintenance-count)
    (var-set maintenance-nonce new-maint-id)
    (ok new-maint-id)
  )
)

(define-public (register-contractor
  (name (string-ascii 100))
  (license-number (string-ascii 50))
  (contact-info (string-ascii 200))
)
  (let
    (
      (new-contr-id (+ (var-get contractor-nonce) u1))
    )
    (asserts! (> (len name) u0) err-invalid-input)
    (asserts! (> (len license-number) u0) err-invalid-input)
    
    (map-set contractors new-contr-id {
      name: name,
      license-number: license-number,
      contact-info: contact-info,
      active: true,
      total-jobs: u0,
      registered-by: tx-sender
    })
    
    (map-set contractor-principals tx-sender new-contr-id)
    (var-set contractor-nonce new-contr-id)
    (ok new-contr-id)
  )
)

(define-public (assign-contractor
  (maint-id uint)
  (contr-id uint)
)
  (let
    (
      (maintenance (unwrap! (map-get? maintenance-schedules maint-id) err-not-found))
      (contractor (unwrap! (map-get? contractors contr-id) err-not-found))
    )
    (asserts! (get active contractor) err-invalid-status)
    (asserts! (is-eq (get status maintenance) "scheduled") err-invalid-status)
    
    (map-set maintenance-schedules maint-id
      (merge maintenance {
        contractor-id: (some contr-id),
        status: "assigned"
      })
    )
    
    (ok true)
  )
)

(define-public (verify-completion
  (maint-id uint)
  (completion-notes (string-ascii 500))
  (post-maintenance-score uint)
)
  (let
    (
      (maintenance (unwrap! (map-get? maintenance-schedules maint-id) err-not-found))
      (taxiway (unwrap! (map-get? taxiway-segments (get taxiway-id maintenance)) err-not-found))
      (contr-id (unwrap! (get contractor-id maintenance) err-not-scheduled))
      (contractor (unwrap! (map-get? contractors contr-id) err-not-found))
    )
    (asserts! (is-eq (get status maintenance) "assigned") err-invalid-status)
    (asserts! (<= post-maintenance-score u100) err-invalid-input)
    
    (map-set maintenance-schedules maint-id
      (merge maintenance {
        status: "completed",
        completed-at: (some block-height),
        completion-notes: (some completion-notes),
        post-maintenance-score: (some post-maintenance-score)
      })
    )
    
    (map-set taxiway-segments (get taxiway-id maintenance)
      (merge taxiway {
        current-visibility-score: post-maintenance-score,
        current-condition: (if (>= post-maintenance-score u90) "excellent" 
                            (if (>= post-maintenance-score u70) "good" "poor")),
        last-maintenance: (some block-height)
      })
    )
    
    (map-set contractors contr-id
      (merge contractor {
        total-jobs: (+ (get total-jobs contractor) u1)
      })
    )
    
    (ok true)
  )
)

(define-public (update-taxiway-status (tw-id uint) (active bool))
  (let
    (
      (taxiway (unwrap! (map-get? taxiway-segments tw-id) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set taxiway-segments tw-id
      (merge taxiway { active: active })
    )
    (ok true)
  )
)

(define-public (update-contractor-status (contr-id uint) (active bool))
  (let
    (
      (contractor (unwrap! (map-get? contractors contr-id) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set contractors contr-id
      (merge contractor { active: active })
    )
    (ok true)
  )
)
