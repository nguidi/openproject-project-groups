# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "open_project/project_groups/version"

Gem::Specification.new do |s|
  s.name        = "openproject-project_groups"
  s.version     = OpenProject::ProjectGroups::VERSION
  s.authors     = "Neri Guidi"
  s.email       = "neri.guidi@gmail.com"
  s.homepage    = "https://github.com/neriguidi/openproject-project_groups"
  s.summary     = "OpenProject Project Groups"
  s.description = "Project-scoped group membership: add users to reusable groups " \
                  "per project, materialized as native project members with the " \
                  "group's roles."
  s.license     = "GPL-3.0"

  s.files = Dir["{app,config,db,doc,lib}/**/*"] +
            %w[CHANGELOG.md README.md DEVELOPMENT.md]

  s.metadata["rubygems_mfa_required"] = "true"

  s.add_dependency "rails"
end
