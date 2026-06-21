# Runtime smoke check, run via `rails runner` inside the built production image.
# Booting the app in production eager-loads all code (catches autoload/Zeitwerk
# issues dev's lazy loading hides), then we assert the plugin is wired up.
mods   = OpenProject::AccessControl.available_project_modules.map(&:to_s)
tables = ActiveRecord::Base.connection.tables.grep(/project_groups/).sort
perms  = OpenProject::AccessControl.permissions.map { |p| p.name.to_s }.grep(/project_group/).sort

ok = mods.include?("project_groups") &&
     tables.size == 4 &&
     perms.include?("manage_project_group_members")

puts "SMOKE_RESULT ok=#{ok} module=#{mods.include?('project_groups')} " \
     "tables=#{tables.inspect} perms=#{perms.inspect} version=#{OpenProject::ProjectGroups::VERSION}"

exit(ok ? 0 : 1)
