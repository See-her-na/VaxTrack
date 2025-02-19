;; Complete Immunization Management System
;; Focus: Full validation, scheduling, and comprehensive tracking

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
(define-constant ERR-DOSE-LIMIT (err u309))
(define-constant ERR-TIMING-GAP (err u310))
(define-constant ERR-INVALID-DATA (err u311))

;; System Parameters
(define-constant MIN-TEMP (- 75))
(define-constant MAX-TEMP 5)
(define-constant DOSE-INTERVAL u28)
(define-constant MAX-DOSES u4)
(define-constant CURRENT-TIME block-height)

;; Data Validation
(define-private (validate-text-short (text (string-ascii 32)))
    (> (len text) u0)
)

(define-private (validate-text-medium (text (string-ascii 100)))
    (> (len text) u0)
)

(define-private (validate-future-date (date uint))
    (> date CURRENT-TIME)
)

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
        storage-site: (string-ascii 100),
        notes: (string-ascii 500)
    }
)

(define-map treatment-records
    { person-id: (string-ascii 32) }
    {
        doses: (list 10 {
            batch-used: (string-ascii 32),
            treatment-date: uint,
            product-administered: (string-ascii 50),
            dose-number: uint,
            provider: principal,
            facility: (string-ascii 100),
            next-appointment: (optional uint)
        }),
        total-doses: uint,
        reactions: (list 5 (string-ascii 200)),
        medical-notes: (optional (string-ascii 200))
    }
)

(define-map authorized-staff 
    principal 
    {
        role: (string-ascii 20),
        facility: (string-ascii 100),
        license-expiry: uint,
        specialty: (string-ascii 50)
    }
)

(define-map facility-registry
    (string-ascii 100)
    {
        location: (string-ascii 200),
        capacity: uint,
        current-stock: uint,
        temp-log: (list 100 {
            check-time: uint,
            reading: int
        }),
        certification: (string-ascii 50),
        operating-hours: (string-ascii 100)
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

(define-private (verify-facility (facility-id (string-ascii 100)))
    (is-some (map-get? facility-registry facility-id))
)

;; Management Functions
(define-public (update-manager (new-manager principal))
    (begin
        (asserts! (is-manager) ERR-NOT-AUTHORIZED)
        (ok (var-set operations-manager new-manager))
    )
)

(define-public (register-staff 
    (staff-address principal)
    (role (string-ascii 20))
    (facility (string-ascii 100))
    (license-expiry uint)
    (specialty (string-ascii 50)))
    (begin
        (asserts! (is-manager) ERR-NOT-AUTHORIZED)
        (asserts! (verify-facility facility) ERR-INVALID-FACILITY)
        (asserts! (validate-future-date license-expiry) ERR-INVALID-DATA)
        (ok (map-set authorized-staff 
            staff-address 
            {
                role: role,
                facility: facility,
                license-expiry: license-expiry,
                specialty: specialty
            }))
    )
)

(define-public (register-facility
    (facility-id (string-ascii 100))
    (location (string-ascii 200))
    (capacity uint)
    (certification (string-ascii 50))
    (operating-hours (string-ascii 100)))
    (begin
        (asserts! (is-manager) ERR-NOT-AUTHORIZED)
        (asserts! (validate-text-medium facility-id) ERR-INVALID-DATA)
        (ok (map-set facility-registry
            facility-id
            {
                location: location,
                capacity: capacity,
                current-stock: u0,
                temp-log: (list),
                certification: certification,
                operating-hours: operating-hours
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
    (storage-site (string-ascii 100))
    (notes (string-ascii 500)))
    (begin
        (asserts! (verify-staff) ERR-NOT-AUTHORIZED)
        (asserts! (validate-text-short batch-id) ERR-INVALID-DATA)
        (asserts! (is-none (map-get? medicine-inventory {batch-id: batch-id})) ERR-BATCH-EXISTS)
        (asserts! (and (>= required-temp MIN-TEMP) (<= required-temp MAX-TEMP)) ERR-TEMP-VIOLATION)
        (asserts! (verify-facility storage-site) ERR-INVALID-FACILITY)
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
                storage-site: storage-site,
                notes: notes
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
        (asserts! (verify-facility facility) ERR-INVALID-FACILITY)
        (match (map-get? medicine-inventory {batch-id: batch-id})
            batch-info (begin
                (asserts! (> (get units-remaining batch-info) u0) ERR-NO-STOCK)
                (asserts! (is-eq (get batch-status batch-info) "active") ERR-INVALID-BATCH)
                (asserts! (<= CURRENT-TIME (get expiry-date batch-info)) ERR-EXPIRED)
                
                (match (map-get? treatment-records {person-id: person-id})
                    existing-record (begin
                        (asserts! (< (get total-doses existing-record) MAX-DOSES) ERR-DOSE-LIMIT)
                        (let ((next-dose (+ (get total-doses existing-record) u1)))
                            (if (> next-dose u1)
                                (asserts! (>= (- CURRENT-TIME 
                                    (get treatment-date (unwrap-panic (element-at 
                                        (get doses existing-record) 
                                        (- next-dose u2))))) 
                                    DOSE-INTERVAL)
                                    ERR-TIMING-GAP)
                                true
                            )
                            
                            (ok (map-set treatment-records
                                {person-id: person-id}
                                {
                                    doses: (unwrap-panic (as-max-len? 
                                        (append (get doses existing-record)
                                            {
                                                batch-used: batch-id,
                                                treatment-date: CURRENT-TIME,
                                                product-administered: (get product-name batch-info),
                                                dose-number: next-dose,
                                                provider: tx-sender,
                                                facility: facility,
                                                next-appointment: (some (+ CURRENT-TIME DOSE-INTERVAL))
                                            }
                                        ) u10)),
                                    total-doses: next-dose,
                                    reactions: (get reactions existing-record),
                                    medical-notes: (get medical-notes existing-record)
                                })))
                    )
                    (ok (map-set treatment-records
                        {person-id: person-id}
                        {
                            doses: (list 
                                {
                                    batch-used: batch-id,
                                    treatment-date: CURRENT-TIME,
                                    product-administered: (get product-name batch-info),
                                    dose-number: u1,
                                    provider: tx-sender,
                                    facility: facility,
                                    next-appointment: (some (+ CURRENT-TIME DOSE-INTERVAL))
                                }),
                            total-doses: u1,
                            reactions: (list),
                            medical-notes: none
                        })))
            )
            ERR-INVALID-BATCH
        )
    )
)

(define-public (record-reaction
    (person-id (string-ascii 32))
    (reaction (string-ascii 200)))
    (begin
        (asserts! (verify-staff) ERR-NOT-AUTHORIZED)
        (match (map-get? treatment-records {person-id: person-id})
            record
            (ok (map-set treatment-records
                {person-id: person-id}
                (merge record {
                    reactions: (unwrap-panic (as-max-len? 
                        (append (get reactions record) reaction)
                        u5))
                })))
            ERR-INVALID-INPUT
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

(define-read-only (verify-batch-status (batch-id (string-ascii 32)))
    (match (map-get? medicine-inventory {batch-id: batch-id})
        batch-info (and
            (is-eq (get batch-status batch-info) "active")
            (> (get units-remaining batch-info) u0)
            (<= CURRENT-TIME (get expiry-date batch-info))
            (<= (get temp-violations batch-info) u2))
        false
    )
)