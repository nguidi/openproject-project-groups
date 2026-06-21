# Verify the admin menu entry (DEV env): is :project_group_roles registered and
# nested under :users_and_permissions?
#
#   docker compose run --rm --no-deps backend \
#     bundle exec rails runner /plugins/openproject-project_groups/dev/verify_admin_menu.rb

items = Redmine::MenuManager.items(:admin_menu, nil)
node  = items.find { |n| n.name == :project_group_roles }
up    = items.find { |n| n.name == :users_and_permissions }
nested = up && up.children.any? { |c| c.name == :project_group_roles }

puts "ADMIN_MENU -> present: #{!node.nil?}, nested_under_users_and_permissions: #{!!nested}"
