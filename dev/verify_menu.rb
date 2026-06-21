# Verify the per-project menu toggle (DEV env). For a project, evaluates the
# project_menu item conditions with the module ON vs OFF and prints whether the
# native "Members" and our "Groups and Members" items are shown. Rolls back.
#
#   docker compose run --rm --no-deps backend \
#     bundle exec rails runner /plugins/openproject-project_groups/dev/verify_menu.rb

def shown?(menu_name, item_name, project)
  node = Redmine::MenuManager.items(menu_name, project).find { |n| n.name == item_name }
  return false unless node

  node.condition.nil? || node.condition.call(project)
end

ActiveRecord::Base.transaction do
  project = Project.first or raise "no project"

  project.enabled_module_names = (project.enabled_module_names - %w[project_groups])
  project.save!(validate: false)
  puts "MODULE OFF -> members: #{shown?(:project_menu, :members, project)}, " \
       "project_groups: #{shown?(:project_menu, :project_groups, project)}"

  project.enabled_module_names = (project.enabled_module_names + %w[project_groups]).uniq
  project.save!(validate: false)
  puts "MODULE ON  -> members: #{shown?(:project_menu, :members, project)}, " \
       "project_groups: #{shown?(:project_menu, :project_groups, project)}"

  raise ActiveRecord::Rollback
end
