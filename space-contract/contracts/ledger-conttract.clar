;; Research Licensing Network - A decentralized platform for scientific discovery licensing
;; Version 3: Complete System with Advanced Financial Model
;; Enables researchers to register and license their scientific breakthroughs with transparent citation tracking

;; System error definitions
(define-constant ACCESS-DENIED-CODE (err u201))
(define-constant ALREADY-LICENSED-CODE (err u202))
(define-constant FUNDS-DEFICIENT-CODE (err u203))
(define-constant DISCOVERY-NOT-FOUND-CODE (err u204))
(define-constant REVIEW-PENDING-CODE (err u205))
(define-constant RESEARCH-SIZE-LIMIT-CODE (err u206))
(define-constant CITATION-BOUNDS-CODE (err u207))
(define-constant PEER-REVIEW-DURATION-CODE (err u208))
(define-constant INVALID-DISCOVERY-REFERENCE-CODE (err u209))
(define-constant IMPACT-BOUNDS-CODE (err u210))
(define-constant RETRACTED-STATUS-CODE (err u211))
(define-constant GRANT-TOO-SMALL-CODE (err u212))
(define-constant JOURNAL-PATH-EMPTY-CODE (err u213))
(define-constant ABSTRACT-EMPTY-CODE (err u214))
(define-constant SYSTEM-MAX-VALUE u2000000000)

;; Core data structures
(define-map scientific-discovery-registry
  { discovery-id: uint }
  {
    principal-investigator: principal,
    current-licensee: (optional principal),
    research-complexity: uint,
    investigator-citation-rate: uint,
    peer-review-period: uint,
    impact-factor: uint,
    approval-timestamp: (optional uint),
    journal-reference: (string-ascii 30),
    discovery-abstract: (string-ascii 20),
    publication-status: (string-ascii 20)
  }
)

(define-map funding-ledger principal uint)

(define-map researcher-citation-index principal uint)

(define-map licensee-portfolio-ledger
  principal
  (list 10 uint)
)

;; System initialization
(define-data-var registry-sequence uint u0)

;; Core business logic implementations
(define-public (register-discovery (research-complexity uint) (investigator-citation-rate uint) (peer-review-period uint) 
                             (impact-factor uint) (journal-reference (string-ascii 30)) 
                             (discovery-abstract (string-ascii 20)))
  (let ((discovery-id (+ (var-get registry-sequence) u1)))
    ;; Input validation suite
    (asserts! (> research-complexity u0) RESEARCH-SIZE-LIMIT-CODE)
    (asserts! (<= investigator-citation-rate u50) CITATION-BOUNDS-CODE)
    (asserts! (and (> peer-review-period u0) (<= peer-review-period u10000)) PEER-REVIEW-DURATION-CODE)
    (asserts! (and (>= impact-factor u1) (<= impact-factor u5)) IMPACT-BOUNDS-CODE)
    ;; Path and metadata validation
    (asserts! (> (len journal-reference) u0) JOURNAL-PATH-EMPTY-CODE)
    (asserts! (> (len discovery-abstract) u0) ABSTRACT-EMPTY-CODE)
    
    ;; Register the new scientific discovery
    (map-set scientific-discovery-registry 
      { discovery-id: discovery-id }
      {
        principal-investigator: tx-sender,
        current-licensee: none,
        research-complexity: research-complexity,
        investigator-citation-rate: investigator-citation-rate,
        peer-review-period: peer-review-period,
        impact-factor: impact-factor,
        approval-timestamp: none,
        journal-reference: journal-reference,
        discovery-abstract: discovery-abstract,
        publication-status: "PUBLISHED"
      }
    )
    
    ;; Update the researcher's portfolio record
    (let 
      (
        (existing-portfolio (default-to (list) (map-get? licensee-portfolio-ledger tx-sender)))
        (refreshed-portfolio (unwrap-panic (as-max-len? (concat (list discovery-id) existing-portfolio) u10)))
      )
      ;; Maintain at most 10 most recent discoveries
      (map-set licensee-portfolio-ledger tx-sender refreshed-portfolio)
    )
    
    (var-set registry-sequence discovery-id)
    (ok discovery-id)
  )
)

(define-public (request-license (discovery-id uint))
  (let (
    (discovery-details (unwrap! (map-get? scientific-discovery-registry { discovery-id: discovery-id }) DISCOVERY-NOT-FOUND-CODE))
    (licensee-funds (default-to u0 (map-get? funding-ledger tx-sender)))
  )
    ;; Validate transaction parameters
    (asserts! (<= discovery-id (var-get registry-sequence)) INVALID-DISCOVERY-REFERENCE-CODE)
    (asserts! (is-none (get current-licensee discovery-details)) ALREADY-LICENSED-CODE)
    (asserts! (is-eq (get publication-status discovery-details) "PUBLISHED") DISCOVERY-NOT-FOUND-CODE)
    (asserts! (>= licensee-funds (get research-complexity discovery-details)) FUNDS-DEFICIENT-CODE)
    
    ;; Update discovery licensing records
    (map-set scientific-discovery-registry { discovery-id: discovery-id }
      (merge discovery-details { 
        current-licensee: (some tx-sender),
        approval-timestamp: (some block-height),
        publication-status: "LICENSE_PENDING"
      })
    )
    
    ;; Execute financial transactions
    (map-set funding-ledger tx-sender (- licensee-funds (get research-complexity discovery-details)))
    (map-set funding-ledger (get principal-investigator discovery-details) 
      (+ (default-to u0 (map-get? funding-ledger (get principal-investigator discovery-details))) (get research-complexity discovery-details)))
    
    (ok true)
  )
)

(define-public (finalize-license (discovery-id uint))
  (let (
    (discovery-details (unwrap! (map-get? scientific-discovery-registry { discovery-id: discovery-id }) DISCOVERY-NOT-FOUND-CODE))
    (licensee-balance (default-to u0 (map-get? funding-ledger tx-sender)))
    (initial-payment (get research-complexity discovery-details))
    (citation-fee (/ (* (get research-complexity discovery-details) (get investigator-citation-rate discovery-details)) u100))
    (impact-premium (/ (* initial-payment (get impact-factor discovery-details)) u100))
    (total-licensing-cost (+ initial-payment citation-fee impact-premium))
  )
    ;; Comprehensive validation checks
    (asserts! (<= discovery-id (var-get registry-sequence)) INVALID-DISCOVERY-REFERENCE-CODE)
    (asserts! (is-eq (get current-licensee discovery-details) (some tx-sender)) ACCESS-DENIED-CODE)
    (asserts! (is-eq (get publication-status discovery-details) "LICENSE_PENDING") DISCOVERY-NOT-FOUND-CODE)
    (asserts! (>= (- block-height (unwrap! (get approval-timestamp discovery-details) DISCOVERY-NOT-FOUND-CODE)) 
                (get peer-review-period discovery-details)) REVIEW-PENDING-CODE)
    (asserts! (>= licensee-balance total-licensing-cost) FUNDS-DEFICIENT-CODE)
    
    ;; Execute citation payment
    (map-set funding-ledger tx-sender (- licensee-balance total-licensing-cost))
    (map-set funding-ledger (get principal-investigator discovery-details) 
      (+ (default-to u0 (map-get? funding-ledger (get principal-investigator discovery-details))) 
         total-licensing-cost)
    )
    
    ;; Update researcher's citation score
    (let ((citation-score (default-to u0 (map-get? researcher-citation-index 
                        (get principal-investigator discovery-details)))))
      (map-set researcher-citation-index
        (get principal-investigator discovery-details)
        (+ citation-score u1)
      )
    )
    
    ;; Update discovery lifecycle status
    (map-set scientific-discovery-registry { discovery-id: discovery-id } 
      (merge discovery-details { publication-status: "LICENSE_COMPLETE" }))
    (ok true)
  )
)

(define-public (retract-publication (discovery-id uint))
  (let (
    (discovery-details (unwrap! (map-get? scientific-discovery-registry { discovery-id: discovery-id }) DISCOVERY-NOT-FOUND-CODE))
  )
    ;; Security validations
    (asserts! (<= discovery-id (var-get registry-sequence)) INVALID-DISCOVERY-REFERENCE-CODE)
    (asserts! (is-eq (get principal-investigator discovery-details) tx-sender) ACCESS-DENIED-CODE)
    (asserts! (is-eq (get publication-status discovery-details) "PUBLISHED") DISCOVERY-NOT-FOUND-CODE)
    
    ;; Change publication status
    (map-set scientific-discovery-registry { discovery-id: discovery-id } 
      (merge discovery-details { publication-status: "RETRACTED" }))
    (ok true)
  )
)

(define-public (fund-research-account (grant-amount uint))
  (let (
    (existing-balance (default-to u0 (map-get? funding-ledger tx-sender)))
  )
    ;; Input validation
    (asserts! (> grant-amount u0) GRANT-TOO-SMALL-CODE)
    (asserts! (<= grant-amount SYSTEM-MAX-VALUE) GRANT-TOO-SMALL-CODE)
    (asserts! (<= (+ existing-balance grant-amount) SYSTEM-MAX-VALUE) GRANT-TOO-SMALL-CODE)
    
    ;; Update account balance
    (map-set funding-ledger tx-sender (+ existing-balance grant-amount))
    (ok true)
  )
)

;; System query interfaces
(define-read-only (query-discovery-metadata (discovery-id uint))
  (map-get? scientific-discovery-registry { discovery-id: discovery-id })
)

(define-read-only (view-research-funds (entity principal))
  (default-to u0 (map-get? funding-ledger entity))
)

(define-read-only (fetch-researcher-impact (researcher principal))
  (default-to u0 (map-get? researcher-citation-index researcher))
)

(define-read-only (list-registered-discoveries (entity principal))
  (default-to (list) (map-get? licensee-portfolio-ledger entity))
)

;; Impact factor calculation
(define-read-only (compute-impact-premium (impact-factor uint))
  (if (and (>= impact-factor u1) (<= impact-factor u5))
      (* impact-factor u1)
      u0)  ;; Failsafe default for invalid parameters
)