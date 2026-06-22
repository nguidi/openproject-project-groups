# Phase 2 live-app verification (DEV env, real BIM data). Exercises exactly what the
# controller does — attach a group, add a member, reconcile — then removes, and prints
# the materialised native Member. Wrapped in a rollback so the dev DB is untouched.
#
#   docker compose run --rm --no-deps backend \
#     bundle exec rails runner /plugins/openproject-project_groups/dev/verify_phase2.rb

result = {}

ActiveRecord::Base.transaction do
  project = Project.first or raise "no project in dev DB"
  group   = Group.find_by(lastname: "BIM Coordinators") || Group.first or raise "no group"
  role    = Role.all.detect(&:member?) or raise "no project (member) role"
  user    = User.where(type: "User").not_locked.where.not(id: group.id).first or raise "no user"

  # Group role-set (what an admin sets up in Phase 3)
  ProjectGroups::GroupRole.find_or_create_by!(group:, role:)

  # What GroupsController#create (attach group) + MembershipsController#create (add member) do:
  assignment = ProjectGroups::Assignment.find_or_create_by!(group:, project:)
  ProjectGroups::Membership.find_or_create_by!(assignment:, user:)
  ProjectGroups::Reconcile.call(user:, project:)

  member = Member.find_by(user_id: user.id, project_id: project.id, entity_type: nil, entity_id: nil)
  result[:context]    = { project: project.identifier, group: group.name, user: user.login, role: role.name }
  result[:after_add]  = { native_member: !member.nil?, roles: member&.roles&.map(&:name) }

  # What MembershipsController#destroy (remove member) does:
  ProjectGroups::Membership.find_by(assignment:, user:).destroy!
  ProjectGroups::Reconcile.call(user:, project:)
  gone = Member.find_by(user_id: user.id, project_id: project.id, entity_type: nil, entity_id: nil).nil?
  result[:after_remove] = { native_member_present: !gone }

  raise ActiveRecord::Rollback
end

puts "PHASE2_VERIFY: #{result.inspect}"
