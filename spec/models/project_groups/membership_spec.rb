# frozen_string_literal: true

#-- copyright
# OpenProject Project Groups plugin.
# Copyright (C) 2026 Neri Guidi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.md and doc/GPL.txt for more details.
#++

require "spec_helper"

RSpec.describe ProjectGroups::Membership do
  shared_let(:group)      { create(:group) }
  shared_let(:project)    { create(:project) }
  shared_let(:user)       { create(:user) }
  shared_let(:assignment) { ProjectGroups::Assignment.create!(group:, project:) }

  it "maps to the prefixed table" do
    expect(described_class.table_name).to eq("project_groups_memberships")
  end

  it "forbids the same user in the same group/project twice" do
    described_class.create!(assignment:, user:)
    expect(described_class.new(assignment:, user:)).not_to be_valid
  end

  it "delegates #group and #project to its assignment" do
    membership = described_class.create!(assignment:, user:)

    expect(membership.group).to eq(group)
    expect(membership.project).to eq(project)
  end
end
