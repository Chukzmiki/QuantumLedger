;; Quantum Research Licensing Network - A decentralized platform for scientific discovery licensing
;; Version 1: Minimal Viable Product (MVP)

;; System error definitions
(define-constant ACCESS-DENIED-CODE (err u201))
(define-constant ALREADY-LICENSED-CODE (err u202))
(define-constant FUNDS-DEFICIENT-CODE (err u203))
(define-constant DISCOVERY-NOT-FOUND-CODE (err u204))

;; Core data structures
(define-map scientific-discovery-registry
  { discovery-id: uint }
  {
    principal-investigator: principal,
    current-licensee: (optional principal),
    research-complexity: uint,
    journal-reference: (string-ascii 30),
    discovery-abstract: (string-ascii 20),
    publication-status: (string-ascii 20)
  }
)

(define-map funding-ledger principal uint)

(define-map licensee-portfolio-ledger
  principal
  (list 10 uint)
)

;; System initialization
(define-data-var registry-sequence uint u0)

;; Core business logic implementations
(define-public (register-discovery (research-complexity uint) 
                             (journal-reference (string-ascii 30)) 
                             (discovery-abstract (string-ascii 20)))
  (let ((discovery-id (+ (var-get registry-sequence) u1)))
    ;; Register the new scientific discovery
    (map-set scientific-discovery-registry 
      { discovery-id: discovery-id }
      {
        principal-investigator: tx-sender,
        current-licensee: none,
        research-complexity: research-complexity,
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
    (asserts! (is-none (get current-licensee discovery-details)) ALREADY-LICENSED-CODE)
    (asserts! (is-eq (get publication-status discovery-details) "PUBLISHED") DISCOVERY-NOT-FOUND-CODE)
    (asserts! (>= licensee-funds (get research-complexity discovery-details)) FUNDS-DEFICIENT-CODE)
    
    ;; Update discovery licensing records
    (map-set scientific-discovery-registry { discovery-id: discovery-id }
      (merge discovery-details { 
        current-licensee: (some tx-sender),
        publication-status: "LICENSED"
      })
    )
    
    ;; Execute financial transactions
    (map-set funding-ledger tx-sender (- licensee-funds (get research-complexity discovery-details)))
    (map-set funding-ledger (get principal-investigator discovery-details) 
      (+ (default-to u0 (map-get? funding-ledger (get principal-investigator discovery-details))) (get research-complexity discovery-details)))
    
    (ok true)
  )
)

(define-public (fund-research-account (grant-amount uint))
  (let (
    (existing-balance (default-to u0 (map-get? funding-ledger tx-sender)))
  )
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

(define-read-only (list-registered-discoveries (entity principal))
  (default-to (list) (map-get? licensee-portfolio-ledger entity))
)