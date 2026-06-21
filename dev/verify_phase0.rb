# Phase 0 smoke test. Run inside the dev backend container:
#   docker compose run --rm -T backend \
#     bundle exec rails runner /plugins/openproject-project_groups/dev/verify_phase0.rb

def section(name)
  puts "=== #{name} ==="
  yield
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
end

section("project_groups tables") do
  puts ActiveRecord::Base.connection.tables.grep(/project_groups/).sort.inspect
end

section("model table_name + count") do
  %w[GroupRole Assignment Membership ManagedMemberRole].each do |m|
    k = ProjectGroups.const_get(m)
    puts "#{k} -> #{k.table_name} (count #{k.count})"
  end
end

section("Group patch associations") do
  %i[project_group_roles project_group_role_set project_group_assignments].each do |a|
    puts "Group##{a}: #{Group.reflect_on_association(a) ? 'OK' : 'MISSING'}"
  end
end

section("project module registered") do
  mods = OpenProject::AccessControl.available_project_modules.map(&:to_s)
  puts "available_project_modules has 'project_groups': #{mods.include?('project_groups')}"
end

section("permissions") do
  perms = OpenProject::AccessControl.permissions.map { |p| p.name.to_s }
  puts perms.select { |n| n.include?("project_group") }.sort.inspect
end

puts "=== DONE ==="
