# Installation, Identity, And Audit Foundations

## Purpose

Task 02 establishes the installation-entry boundary for Core Matrix:
installation bootstrap, authentication identities, product users, invitations,
sessions, and installation-scoped audit logs.

## Aggregate Responsibilities

### Installation

- There is exactly one installation row.
- The installation stores a name, bootstrap state, and global settings JSON.
- Bootstrap state moves from `pending` to `bootstrapped` during first-admin
  creation.

### Identity

- `Identity` owns authentication concerns.
- Email addresses are normalized to lowercase and trimmed whitespace.
- Passwords use `has_secure_password` with the `password_digest` column.
- Disabled identities are represented by `disabled_at`.

### User

- `User` owns installation membership, display name, role, and preferences.
- Roles are `member` or `admin`.
- Active admins are admin users whose identities are not disabled.

### Invitation

- Invitation tokens are stored as SHA-256 digests, not plaintext.
- Invitation tokens are one-time and expiring.
- Consuming an invitation creates a new `Identity` plus `User` for the target
  installation and marks the invitation as consumed.

### Session

- Session tokens are stored as SHA-256 digests, not plaintext.
- Sessions are active only while not expired and not revoked.
- Revocation is explicit through `revoked_at`.

### AuditLog

- Audit logs are scoped to an installation.
- Actor and subject use optional polymorphic references.
- Actor or subject pairs must be complete: type and id must appear together.

## Services

### `Installations::BootstrapFirstAdmin`

- Creates the installation, first identity, first admin user, and the
  `installation.bootstrapped` audit row in a single transaction.
- Rejects a second bootstrap attempt with
  `Installations::BootstrapFirstAdmin::AlreadyBootstrapped`.

### `Invitations::Consume`

- Resolves an invitation from its plaintext token by digest lookup.
- Rejects invalid, consumed, or expired invitations.
- Creates the invited identity and user in one transaction.
- Writes the `invitation.consumed` audit row.

### `Users::GrantAdmin`

- Promotes a member to admin inside the same installation.
- Writes the `user.admin_granted` audit row.

### `Users::RevokeAdmin`

- Demotes an admin to member inside the same installation.
- Refuses to revoke the last active admin with
  `Users::RevokeAdmin::LastAdminError`.
- Writes the `user.admin_revoked` audit row when the revoke succeeds.

## Invariants

- The installation remains single-row.
- `Identity` and `User` stay separate aggregates.
- Admin-safety uses active-admin semantics, not raw admin row count.
- Service orchestration owns side effects; models do not use callbacks for
  bootstrap, invitation consumption, or admin-role changes.
- Secrets are filtered from logs through `config.filter_parameters`.

## Failure Modes

- Second bootstrap attempt raises `AlreadyBootstrapped`.
- Expired invitation consumption raises `ExpiredInvitation`.
- Consumed or unknown invitation tokens raise `InvalidInvitation`.
- Cross-installation admin mutations raise `ArgumentError`.
- Revoking the last active admin raises `LastAdminError`.
