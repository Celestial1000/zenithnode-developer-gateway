;; zenith-node.clar
;; ZenithNode Developer Gateway Contract
;; 
;; This contract serves as a gateway for developers to interact with the Stacks blockchain
;; in a simplified and standardized way. It abstracts complex blockchain interactions into 
;; a unified interface, manages developer accounts, applications, and enforces usage policies.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-ALREADY-REGISTERED (err u1001))
(define-constant ERR-NOT-REGISTERED (err u1002))
(define-constant ERR-APP-ALREADY-EXISTS (err u1003))
(define-constant ERR-APP-NOT-FOUND (err u1004))
(define-constant ERR-RATE-LIMIT-EXCEEDED (err u1005))
(define-constant ERR-INVALID-PARAMETERS (err u1006))
(define-constant ERR-SUSPENDED-ACCOUNT (err u1007))
(define-constant ERR-INSUFFICIENT-FUNDS (err u1008))
(define-constant ERR-OPERATION-FAILED (err u1009))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-APPS-PER-DEVELOPER u5)
(define-constant DEFAULT-DAILY-RATE-LIMIT u1000)
(define-constant PREMIUM-DAILY-RATE-LIMIT u10000)

;; Data storage

;; Developer information
(define-map developers
  { address: principal }
  {
    name: (optional (string-ascii 100)),
    email: (optional (string-ascii 100)),
    registration-time: uint,
    status: (string-ascii 20),  ;; "active", "suspended", "premium"
    rate-limit: uint
  }
)

;; Registered applications for each developer
(define-map developer-apps
  { developer: principal, app-id: (string-ascii 50) }
  {
    name: (string-ascii 100),
    description: (optional (string-utf8 500)),
    created-at: uint,
    status: (string-ascii 20),  ;; "active", "suspended"
    api-key: (string-ascii 64),
    domain: (optional (string-ascii 100))
  }
)

;; Tracks usage metrics for rate limiting
(define-map usage-metrics
  { developer: principal, date: uint }
  { 
    request-count: uint,
    last-request-time: uint
  }
)

;; List of apps owned by each developer
(define-map developer-app-list
  { developer: principal }
  { app-ids: (list 20 (string-ascii 50)) }
)

;; Admin list
(define-map admins
  { address: principal }
  { role: (string-ascii 20) }  ;; "admin", "super-admin"
)

;; Global variables
(define-data-var total-developers uint u0)
(define-data-var total-applications uint u0)

;; Private functions

;; Checks if principal is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; Checks if principal is an admin
(define-private (is-admin (address principal))
  (match (map-get? admins { address: address })
    admin true
    false
  )
)

;; Gets current block date (simplified to block height / 144 for daily approximation)
(define-private (get-current-date)
  (/ block-height u144)
)

;; Checks if a developer is registered
(define-private (is-developer-registered (address principal))
  (is-some (map-get? developers { address: address }))
)

;; Checks if a developer is active
(define-private (is-developer-active (address principal))
  (match (map-get? developers { address: address })
    developer (is-eq (get status developer) "active")
    false
  )
)

;; Checks if a developer has reached the maximum number of allowed apps
(define-private (has-max-apps (address principal))
  (match (map-get? developer-app-list { developer: address })
    app-list (>= (len (get app-ids app-list)) MAX-APPS-PER-DEVELOPER)
    false
  )
)

;; Checks if rate limit is exceeded for the current date
(define-private (is-rate-limited (address principal))
  (let (
    (current-date (get-current-date))
    (dev-rate-limit (get-developer-rate-limit address))
  )
    (match (map-get? usage-metrics { developer: address, date: current-date })
      metrics (>= (get request-count metrics) dev-rate-limit)
      false
    )
  )
)

;; Gets the rate limit for a developer based on their status
(define-private (get-developer-rate-limit (address principal))
  (match (map-get? developers { address: address })
    developer (get rate-limit developer)
    DEFAULT-DAILY-RATE-LIMIT
  )
)

;; Updates usage metrics for a developer
(define-private (update-usage-metrics (address principal))
  (let (
    (current-date (get-current-date))
    (current-time block-height)
  )
    (match (map-get? usage-metrics { developer: address, date: current-date })
      metrics
        (map-set usage-metrics
          { developer: address, date: current-date }
          { 
            request-count: (+ (get request-count metrics) u1),
            last-request-time: current-time
          }
        )
      ;; First request of the day
      (map-set usage-metrics
        { developer: address, date: current-date }
        { 
          request-count: u1,
          last-request-time: current-time
        }
      )
    )
  )
)

;; Generates a unique API key (simplified implementation)
(define-private (generate-api-key (developer principal) (app-id (string-ascii 50)))
  (concat (concat (to-ascii developer) "-") app-id)
)

;; Adds app ID to developer's app list
(define-private (add-app-to-list (developer principal) (app-id (string-ascii 50)))
  (match (map-get? developer-app-list { developer: developer })
    existing-list 
      (map-set developer-app-list
        { developer: developer }
        { app-ids: (unwrap! (as-max-len? (append (get app-ids existing-list) app-id) u20) false) }
      )
    ;; First app for this developer
    (map-set developer-app-list
      { developer: developer }
      { app-ids: (list app-id) }
    )
  )
)

;; Removes app ID from developer's app list
(define-private (remove-app-from-list (developer principal) (app-id (string-ascii 50)))
  (match (map-get? developer-app-list { developer: developer })
    existing-list 
      (map-set developer-app-list
        { developer: developer }
        { app-ids: (filter (lambda (id) (not (is-eq id app-id))) (get app-ids existing-list)) }
      )
    false
  )
)

;; Read-only functions

;; Get developer information
(define-read-only (get-developer-info (address principal))
  (map-get? developers { address: address })
)

;; Get application details
(define-read-only (get-app-details (developer principal) (app-id (string-ascii 50)))
  (map-get? developer-apps { developer: developer, app-id: app-id })
)

;; Get developer's applications
(define-read-only (get-developer-apps (developer principal))
  (map-get? developer-app-list { developer: developer })
)

;; Get developer usage metrics for the current date
(define-read-only (get-current-usage (developer principal))
  (let ((current-date (get-current-date)))
    (map-get? usage-metrics { developer: developer, date: current-date })
  )
)

;; Check if API key is valid
(define-read-only (is-api-key-valid (developer principal) (app-id (string-ascii 50)) (api-key (string-ascii 64)))
  (match (map-get? developer-apps { developer: developer, app-id: app-id })
    app (is-eq (get api-key app) api-key)
    false
  )
)

;; Public functions

;; Register as a developer
(define-public (register-developer (name (optional (string-ascii 100))) (email (optional (string-ascii 100))))
  (let ((caller tx-sender))
    (asserts! (not (is-developer-registered caller)) ERR-ALREADY-REGISTERED)
    
    ;; Register the developer
    (map-set developers
      { address: caller }
      {
        name: name,
        email: email,
        registration-time: block-height,
        status: "active",
        rate-limit: DEFAULT-DAILY-RATE-LIMIT
      }
    )
    
    ;; Update total developers count
    (var-set total-developers (+ (var-get total-developers) u1))
    
    (ok true)
  )
)

;; Update developer profile
(define-public (update-profile (name (optional (string-ascii 100))) (email (optional (string-ascii 100))))
  (let ((caller tx-sender))
    (asserts! (is-developer-registered caller) ERR-NOT-REGISTERED)
    
    (match (map-get? developers { address: caller })
      existing-dev
        (map-set developers
          { address: caller }
          {
            name: name,
            email: email,
            registration-time: (get registration-time existing-dev),
            status: (get status existing-dev),
            rate-limit: (get rate-limit existing-dev)
          }
        )
      (err ERR-NOT-REGISTERED)
    )
    
    (ok true)
  )
)

;; Register a new application
(define-public (register-application 
  (app-id (string-ascii 50)) 
  (name (string-ascii 100)) 
  (description (optional (string-utf8 500)))
  (domain (optional (string-ascii 100))))
  
  (let (
    (caller tx-sender)
    (api-key (generate-api-key caller app-id))
  )
    ;; Validate developer
    (asserts! (is-developer-registered caller) ERR-NOT-REGISTERED)
    (asserts! (is-developer-active caller) ERR-SUSPENDED-ACCOUNT)
    (asserts! (not (has-max-apps caller)) ERR-RATE-LIMIT-EXCEEDED)
    
    ;; Check if app ID already exists for this developer
    (asserts! (is-none (map-get? developer-apps { developer: caller, app-id: app-id })) ERR-APP-ALREADY-EXISTS)
    
    ;; Register the application
    (map-set developer-apps
      { developer: caller, app-id: app-id }
      {
        name: name,
        description: description,
        created-at: block-height,
        status: "active",
        api-key: api-key,
        domain: domain
      }
    )
    
    ;; Add to developer's app list
    (asserts! (add-app-to-list caller app-id) ERR-OPERATION-FAILED)
    
    ;; Update total applications count
    (var-set total-applications (+ (var-get total-applications) u1))
    
    (ok api-key)
  )
)

;; Update application details
(define-public (update-application 
  (app-id (string-ascii 50)) 
  (name (string-ascii 100)) 
  (description (optional (string-utf8 500)))
  (domain (optional (string-ascii 100))))
  
  (let ((caller tx-sender))
    ;; Validate developer
    (asserts! (is-developer-registered caller) ERR-NOT-REGISTERED)
    (asserts! (is-developer-active caller) ERR-SUSPENDED-ACCOUNT)
    
    ;; Check if app exists
    (match (map-get? developer-apps { developer: caller, app-id: app-id })
      existing-app
        (map-set developer-apps
          { developer: caller, app-id: app-id }
          {
            name: name,
            description: description,
            created-at: (get created-at existing-app),
            status: (get status existing-app),
            api-key: (get api-key existing-app),
            domain: domain
          }
        )
      (err ERR-APP-NOT-FOUND)
    )
    
    (ok true)
  )
)

;; Delete application
(define-public (delete-application (app-id (string-ascii 50)))
  (let ((caller tx-sender))
    ;; Validate developer
    (asserts! (is-developer-registered caller) ERR-NOT-REGISTERED)
    
    ;; Check if app exists
    (asserts! (is-some (map-get? developer-apps { developer: caller, app-id: app-id })) ERR-APP-NOT-FOUND)
    
    ;; Delete the application
    (map-delete developer-apps { developer: caller, app-id: app-id })
    
    ;; Remove from developer's app list
    (asserts! (remove-app-from-list caller app-id) ERR-OPERATION-FAILED)
    
    ;; Update total applications count
    (var-set total-applications (- (var-get total-applications) u1))
    
    (ok true)
  )
)

;; Regenerate API key for an application
(define-public (regenerate-api-key (app-id (string-ascii 50)))
  (let (
    (caller tx-sender)
    (new-api-key (generate-api-key caller app-id))
  )
    ;; Validate developer
    (asserts! (is-developer-registered caller) ERR-NOT-REGISTERED)
    (asserts! (is-developer-active caller) ERR-SUSPENDED-ACCOUNT)
    
    ;; Check if app exists
    (match (map-get? developer-apps { developer: caller, app-id: app-id })
      existing-app
        (map-set developer-apps
          { developer: caller, app-id: app-id }
          {
            name: (get name existing-app),
            description: (get description existing-app),
            created-at: (get created-at existing-app),
            status: (get status existing-app),
            api-key: new-api-key,
            domain: (get domain existing-app)
          }
        )
      (err ERR-APP-NOT-FOUND)
    )
    
    (ok new-api-key)
  )
)

;; Make a gateway request (simulated function that would handle various blockchain operations)
(define-public (gateway-request 
  (app-id (string-ascii 50)) 
  (api-key (string-ascii 64)) 
  (request-type (string-ascii 50))
  (params (list 10 (string-utf8 200))))
  
  (let ((caller tx-sender))
    ;; Validate developer
    (asserts! (is-developer-registered caller) ERR-NOT-REGISTERED)
    (asserts! (is-developer-active caller) ERR-SUSPENDED-ACCOUNT)
    (asserts! (not (is-rate-limited caller)) ERR-RATE-LIMIT-EXCEEDED)
    
    ;; Validate API key
    (asserts! (is-api-key-valid caller app-id api-key) ERR-NOT-AUTHORIZED)
    
    ;; Update usage metrics
    (update-usage-metrics caller)
    
    ;; Process request (simplified implementation)
    ;; In a real implementation, this would perform different blockchain operations
    ;; based on the request-type parameter
    (ok { status: "success", request-id: (to-uint (hash request-type)) })
  )
)

;; Admin functions

;; Add an admin (only contract owner can do this)
(define-public (add-admin (address principal) (role (string-ascii 20)))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set admins { address: address } { role: role })
    (ok true)
  )
)

;; Update developer status (admins only)
(define-public (update-developer-status (developer principal) (status (string-ascii 20)) (rate-limit uint))
  (begin
    (asserts! (or (is-contract-owner) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (is-developer-registered developer) ERR-NOT-REGISTERED)
    
    (match (map-get? developers { address: developer })
      existing-dev
        (map-set developers
          { address: developer }
          {
            name: (get name existing-dev),
            email: (get email existing-dev),
            registration-time: (get registration-time existing-dev),
            status: status,
            rate-limit: rate-limit
          }
        )
      (err ERR-NOT-REGISTERED)
    )
    
    (ok true)
  )
)

;; Update application status (admins only)
(define-public (update-application-status (developer principal) (app-id (string-ascii 50)) (status (string-ascii 20)))
  (begin
    (asserts! (or (is-contract-owner) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    (match (map-get? developer-apps { developer: developer, app-id: app-id })
      existing-app
        (map-set developer-apps
          { developer: developer, app-id: app-id }
          {
            name: (get name existing-app),
            description: (get description existing-app),
            created-at: (get created-at existing-app),
            status: status,
            api-key: (get api-key existing-app),
            domain: (get domain existing-app)
          }
        )
      (err ERR-APP-NOT-FOUND)
    )
    
    (ok true)
  )
)

;; Get total statistics (admins only)
(define-read-only (get-statistics)
  (begin
    (asserts! (or (is-contract-owner) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    (ok {
      total-developers: (var-get total-developers),
      total-applications: (var-get total-applications)
    })
  )
)