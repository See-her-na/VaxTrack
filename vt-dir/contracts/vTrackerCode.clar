;; Basic Immunization Management System
;; Focus: Core data structure and basic operations

;; System Management
(define-data-var operations-manager principal tx-sender)

;; Error States
(define-constant ERR-NOT-AUTHORIZED (err u301))
(define-constant ERR-INVALID-BATCH (err u302))
(define-constant ERR-BATCH-EXISTS (err u303))
(define-constant ERR-NO-STOCK (err u304))
(define-constant ERR-INVALID-INPUT (err u305))

;; Core Data Storage
(define-map medicine-inventory
    { batch-id: (string-ascii 32) }
    {
        manufacturer: (string-ascii 50),
        product-name: (string-ascii 50),
        production-date: uint,
        expiry-date: uint,
        units-remaining: uint,
        batch-status: (string-ascii 20)
    }
)

(define-map treatment-records
    { person-id: (string-ascii 32) }
    {
        doses: (list 5 {
            batch-used: (string-ascii 32),
            treatment-date: uint,
            provider: principal
        }),
        total-doses: uint
    }
)

(define-map authorized-staff 
    principal 
    {
        role: (string-ascii 20),
        facility: (string-ascii 100)
    }
)

;; Core Functions
(define-private (is-manager)
    (is-eq tx-sender (var-get operations-manager))
)

(define-private (verify-staff)
    (is-some (map-get? authorized-staff tx-sender))
)

;; Management Functions
(define-public (register-staff 
    (staff-address principal)
    (role (string-ascii 20))
    (facility (string-ascii 100)))
    (begin
        (asserts! (is-manager) ERR-NOT-AUTHORIZED)
        (ok (map-set authorized-staff 
            staff-address 
            {
                role: role,
                facility: facility
            }))
    )
)

(define-public (add-inventory 
    (batch-id (string-ascii 32))
    (manufacturer (string-ascii 50))
    (product-name (string-ascii 50))
    (production-date uint)
    (expiry-date uint)
    (initial-units uint))
    (begin
        (asserts! (verify-staff) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? medicine-inventory {batch-id: batch-id})) ERR-BATCH-EXISTS)
        (ok (map-set medicine-inventory 
            {batch-id: batch-id}
            {
                manufacturer: manufacturer,
                product-name: product-name,
                production-date: production-date,
                expiry-date: expiry-date,
                units-remaining: initial-units,
                batch-status: "active"
            }))
    )
)

(define-public (record-treatment
    (person-id (string-ascii 32))
    (batch-id (string-ascii 32)))
    (begin
        (asserts! (verify-staff) ERR-NOT-AUTHORIZED)
        (match (map-get? medicine-inventory {batch-id: batch-id})
            batch-info (begin
                (asserts! (> (get units-remaining batch-info) u0) ERR-NO-STOCK)
                (match (map-get? treatment-records {person-id: person-id})
                    existing-record 
                    (ok (map-set treatment-records
                        {person-id: person-id}
                        {
                            doses: (unwrap-panic (as-max-len? 
                                (append (get doses existing-record)
                                    {
                                        batch-used: batch-id,
                                        treatment-date: block-height,
                                        provider: tx-sender
                                    }
                                ) u5)),
                            total-doses: (+ (get total-doses existing-record) u1)
                        }))
                    (ok (map-set treatment-records
                        {person-id: person-id}
                        {
                            doses: (list 
                                {
                                    batch-used: batch-id,
                                    treatment-date: block-height,
                                    provider: tx-sender
                                }),
                            total-doses: u1
                        })))
            )
            ERR-INVALID-BATCH
        )
    )
)

;; Read Functions
(define-read-only (get-inventory (batch-id (string-ascii 32)))
    (map-get? medicine-inventory {batch-id: batch-id})
)

(define-read-only (get-treatment-history (person-id (string-ascii 32)))
    (map-get? treatment-records {person-id: person-id})
)