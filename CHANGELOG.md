# Changelog

All notable changes to the OpenProject Project Groups plugin are documented in
this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-21

Initial release. Project-scoped group membership for OpenProject: add users to a
reusable group **per project**, materialized as native project members carrying
the group's roles — without the native cross-project propagation.

### Added
- Rails engine (`OpenProject::Plugins::ActsAsOpEngine`) registering the
  **"Groups and Members"** per-project module, its `view_project_groups` and
  `manage_project_group_members` permissions, project menu entry, and a `Group`
  model patch.
- Data model: `project_groups_group_roles`, `project_groups_assignments`,
  `project_groups_memberships`, and `project_groups_managed_member_roles` tables
  with their migrations.
- `ProjectGroups::Reconcile` service (per user/project) and `Reconcile.for_group`
  fan-out, backed by managed-member-role bookkeeping so reconciliation only ever
  touches roles the plugin owns. Covered by the 8 RSpec scenarios.
- `ProjectGroups::ReconcileJob` for background fan-out on the Good Job queue.
- Project UI ("Groups and Members" page) to attach/detach groups and add/remove
  members, with the native Members menu hidden where the module is enabled.
- Admin UI (Administration ▸ Users & Permissions ▸ Group role-sets) to define
  each group's role-set; `SetGroupRoleSet` applies the change synchronously and
  fans member reconciliation out to background `ReconcileJob`s.
- All three screens rebuilt with OpenProject's native Primer ViewComponents.
- Operations: `ProjectGroups::ReconcileAll` service + `rake
  project_groups:reconcile_all` (drift repair) and `rake project_groups:check`
  (core-propagation conflict report), plus an in-page conflict warning banner.
- Deployment kit under `deploy/` (multi-stage `Dockerfile.slim`, `build.sh`,
  `Gemfile.plugins`, smoke test, and `DEPLOYMENT.md`).
- RSpec suite under `spec/`: the 8 reconciliation scenarios plus `ReconcileAll`,
  `SetGroupRoleSet`, and `ReconcileJob` service/worker specs, and model + `Group`
  patch specs (validations, `Assignment#roles`, `Membership` delegations,
  `table_name_prefix` and FK-cascade wiring).

[Unreleased]: https://github.com/neriguidi/openproject-project_groups/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/neriguidi/openproject-project_groups/releases/tag/v0.1.0
