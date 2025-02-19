;; Improved Immunization Management System
;; Focus: Added temperature monitoring and validation

;; System Management
(define-data-var operations-manager principal tx-sender)

;; Error States
(define-constant ERR-NOT-AUTHORIZED (err u301))
(define-constant ERR-INVALID-BATCH (err u302))
(define-constant ERR-BATCH-EXISTS (err u303))
(define-constant ERR-NO-STOCK (err u304))
(define-constant ERR-INVALID-INPUT (err u305))
(define-constant ERR-TEMP-VIOLATION (err u306))
(define-constant ERR-EXPIRED (err u307))
(define-constant ERR-INVALID-FACILITY (err u308))

;; System Parameters
(define-constant MIN-TEMP (- 75))
(define-constant MAX-TEMP 5)
(define-constant CURRENT-TIME block-height)

;; Core Data Storage
(define-map medicine-inventory
    { batch-id: (string-ascii 32) }
    {
        manufacturer: (string-ascii 50),
        product-name: (string-ascii 50),
        production-date: uint,
        expiry-date: uint,
        units-remaining: uint,
        required-temp: int,
        batch-status: (string-ascii 20),
        temp-violations: uint,
        storage-site: (string-ascii 100)
    }
)

(define-map treatment-records
    { person-id: (string-ascii 32) }
    {
        doses: (list 5 {
            batch-used: (string-ascii 32),
            treatment-date: uint,
            provider: principal,
            facility: (string-ascii 100)
        }),
        total-doses: uint,
        reactions: (list 3 (string-ascii 200))
    }
)

(define-map authorized-staff 
    principal 
    {
        role: (string-ascii 20),
        facility: (string-ascii 100),
        license-expiry: uint
    }
)

(define-map facility-registry
    (string-ascii 100)
    {
        location: (string-ascii 200),
        capacity: uint,
        current-stock: uint,
        temp-log: (list 50 {
            check-time: uint,
            reading: int
        })
    }
)

;; Core Functions
(define-private (is-manager)
    (is-eq tx-sender (var-get operations-manager))
)

(define-private (verify-staff)
    (match (map-get? authorized-staff tx-sender)
        staff-info (>= (get license-expiry staff-info) CURRENT-TIME)
        false
    )
)

;; Management Functions
(define-public (register-staff 
    (staff-address principal)
    (role (string-ascii 20))
    (facility (string-ascii 100))
    (license-expiry uint))
    (begin
        (asserts! (is-manager) ERR-NOT-AUTHORIZED)
        (ok (map-set authorized-staff 
            staff-address 
            {
                role: role,
                facility: facility,
                license-expiry: license-expiry
            }))
    )
)

(define-public (register-facility
    (facility-id (string-ascii 100))
    (location (string-ascii 200))
    (capacity uint))
    (begin
        (asserts! (is-manager) ERR-NOT-AUTHORIZED)
        (ok (map-set facility-registry
            facility-id
            {
                location: location,
                capacity: capacity,
                current-stock: u0,
                temp-log: (list)
            }))
    )
)

(define-public (add-inventory 
    (batch-id (string-ascii 32))
    (manufacturer (string-ascii 50))
    (product-name (string-ascii 50))
    (production-date uint)
    (expiry-date uint)
    (initial-units uint)
    (required-temp int)
    (storage-site (string-ascii 100)))
    (begin
        (asserts! (verify-staff) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? medicine-inventory {batch-id: batch-id})) ERR-BATCH-EXISTS)
        (asserts! (and (>= required-temp MIN-TEMP) (<= required-temp MAX-TEMP)) ERR-TEMP-VIOLATION)
        (ok (map-set medicine-inventory 
            {batch-id: batch-id}
            {
                manufacturer: manufacturer,
                product-name: product-name,
                production-date: production-date,
                expiry-date: expiry-date,
                units-remaining: initial-units,
                required-temp: required-temp,
                batch-status: "active",
                temp-violations: u0,
                storage-site: storage-site
            }))
    )
)

(define-public (record-temp
    (batch-id (string-ascii 32))
    (temperature int))
    (begin
        (asserts! (verify-staff) ERR-NOT-AUTHORIZED)
        (match (map-get? medicine-inventory {batch-id: batch-id})
            batch-info 
            (ok (map-set medicine-inventory 
                {batch-id: batch-id}
                (merge batch-info {
                    temp-violations: (+ (get temp-violations batch-info) u1),
                    batch-status: (if (> (get temp-violations batch-info) u2) 
                                "compromised" 
                                (get batch-status batch-info))
                })))
            ERR-INVALID-BATCH
        )
    )
)

(define-public (record-treatment
    (person-id (string-ascii 32))
    (batch-id (string-ascii 32))
    (facility (string-ascii 100)))
    (begin
        (asserts! (verify-staff) ERR-NOT-AUTHORIZED)
        (match (map-get? medicine-inventory {batch-id: batch-id})
            batch-info (begin
                (asserts! (> (get units-remaining batch-info) u0) ERR-NO-STOCK)
                (asserts! (is-eq (get batch-status batch-info) "active") ERR-INVALID-BATCH)
                (asserts! (<= CURRENT-TIME (get expiry-date batch-info)) ERR-EXPIRED)
                (match (map-get? treatment-records {person-id: person-id})
                    existing-record 
                    (ok (map-set treatment-records
                        {person-id: person-id}
                        {
                            doses: (unwrap-panic (as-max-len? 
                                (append (get doses existing-record)
                                    {
                                        batch-used: batch-id,
                                        treatment-date: CURRENT-TIME,
                                        provider: tx-sender,
                                        facility: facility
                                    }
                                ) u5)),
                            total-doses: (+ (get total-doses existing-record) u1),
                            reactions: (get reactions existing-record)
                        }))
                    (ok (map-set treatment-records
                        {person-id: person-id}
                        {
                            doses: (list 
                                {
                                    batch-used: batch-id,
                                    treatment-date: CURRENT-TIME,
                                    provider: tx-sender,
                                    facility: facility
                                }),
                            total-doses: u1,
                            reactions: (list)
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

(define-read-only (get-facility-info (facility-id (string-ascii 100)))
    (map-get? facility-registry facility-id)
)