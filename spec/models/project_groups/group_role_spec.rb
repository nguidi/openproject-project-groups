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

RSpec.describe ProjectGroups::GroupRole do
  shared_let(:group) { create(:group) }
  shared_let(:role)  { create(:project_role) }

  it "maps to the prefixed table (table_name_prefix wiring)" do
    expect(described_class.table_name).to eq("project_groups_group_roles")
  end

  it "is valid with a group and a role" do
    expect(described_class.new(group:, role:)).to be_valid
  end

  it "forbids the same role twice in one group" do
    described_class.create!(group:, role:)
    expect(described_class.new(group:, role:)).not_to be_valid
  end

  it "allows the same role in a different group" do
    described_class.create!(group:, role:)
    expect(described_class.new(group: create(:group), role:)).to be_valid
  end
end
