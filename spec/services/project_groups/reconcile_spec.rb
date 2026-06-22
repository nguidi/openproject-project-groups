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

# The §4 reconciliation scenarios. These pin the correctness invariants before any
# UI is built on top: project-scoping, "direct wins", shared roles, role-set edits,
# idempotency, group removal, and cascade cleanup.
RSpec.describe ProjectGroups::Reconcile do
  shared_let(:project)       { create(:project) }
  shared_let(:other_project) { create(:project) }
  shared_let(:user)          { create(:user) }
  shared_let(:role_a)        { create(:project_role) }   # e.g. "Member"
  shared_let(:role_b)        { create(:project_role) }   # e.g. "Reviewer"

  # --- helpers -------------------------------------------------------------
  def group_with_roles(*roles)
    create(:group).tap { |g| roles.each { |r| ProjectGroups::GroupRole.create!(group: g, role: r) } }
  end

  def add_to_group(group, user, project)
    assignment = ProjectGroups::Assignment.find_or_create_by!(group:, project:)
    ProjectGroups::Membership.create!(assignment:, user:)
  end

  def member_for(usr, prj)
    Member.find_by(user_id: usr.id, project_id: prj.id, entity_type: nil, entity_id: nil)
  end

  def role_ids_for(usr, prj)
    member_for(usr, prj)&.member_roles&.map(&:role_id) || []
  end

  # --- 1: add scopes to one project ---------------------------------------
  it "materialises a project-scoped member with the group's roles, only in that project" do
    g = group_with_roles(role_a)
    add_to_group(g, user, project)

    described_class.call(user:, project:)

    expect(member_for(user, project)).to be_present
    expect(role_ids_for(user, project)).to contain_exactly(role_a.id)
    expect(member_for(user, other_project)).to be_nil
  end

  # --- 2: remove cleans only ours -----------------------------------------
  it "removes the materialised member when the user leaves the group" do
    g = group_with_roles(role_a)
    membership = add_to_group(g, user, project)
    described_class.call(user:, project:)
    expect(member_for(user, project)).to be_present

    membership.destroy!
    described_class.call(user:, project:)

    expect(member_for(user, project)).to be_nil
    expect(ProjectGroups::ManagedMemberRole.count).to eq(0)
  end

  # --- 3: direct wins ------------------------------------------------------
  context "when the user already holds a role directly (manual member)" do
    it "adds only the group's other roles and never strips the direct one" do
      create(:member, principal: user, project:, roles: [role_a])  # manual, direct
      g = group_with_roles(role_a, role_b)
      membership = add_to_group(g, user, project)

      described_class.call(user:, project:)

      # role_a kept (direct, not duplicated), role_b added and owned by us
      expect(role_ids_for(user, project)).to contain_exactly(role_a.id, role_b.id)
      expect(ProjectGroups::ManagedMemberRole.count).to eq(1)

      membership.destroy!
      described_class.call(user:, project:)

      # role_b (ours) removed; role_a (direct) untouched; member stays
      expect(role_ids_for(user, project)).to contain_exactly(role_a.id)
      expect(member_for(user, project)).to be_present
    end
  end

  # --- 4: two groups sharing a role ---------------------------------------
  it "keeps a shared role when the user leaves one of two groups granting it" do
    g1 = group_with_roles(role_a)
    g2 = group_with_roles(role_a, role_b)
    add_to_group(g1, user, project)
    m2 = add_to_group(g2, user, project)
    described_class.call(user:, project:)
    expect(role_ids_for(user, project)).to contain_exactly(role_a.id, role_b.id)

    m2.destroy!
    described_class.call(user:, project:)

    # role_a still wanted by g1 → kept; role_b only from g2 → removed
    expect(role_ids_for(user, project)).to contain_exactly(role_a.id)
  end

  # --- 5: role-set edit, immediate ----------------------------------------
  it "propagates a group's role-set change to existing members" do
    g = group_with_roles(role_a)
    add_to_group(g, user, project)
    described_class.call(user:, project:)

    ProjectGroups::GroupRole.create!(group: g, role: role_b)  # add a role
    described_class.for_group(g)
    expect(role_ids_for(user, project)).to contain_exactly(role_a.id, role_b.id)

    ProjectGroups::GroupRole.find_by(group: g, role: role_a).destroy! # remove a role
    described_class.for_group(g)
    expect(role_ids_for(user, project)).to contain_exactly(role_b.id)
  end

  # --- 6: idempotency ------------------------------------------------------
  it "is idempotent" do
    g = group_with_roles(role_a, role_b)
    add_to_group(g, user, project)
    described_class.call(user:, project:)

    expect { described_class.call(user:, project:) }
      .to change(Member, :count).by(0)
      .and change(MemberRole, :count).by(0)
      .and change(ProjectGroups::ManagedMemberRole, :count).by(0)
  end

  # --- 7: group removed from the project (assignment destroyed) -----------
  it "removes materialised roles when the group is detached from the project" do
    g = group_with_roles(role_a)
    assignment = ProjectGroups::Assignment.create!(group: g, project:)
    ProjectGroups::Membership.create!(assignment:, user:)
    described_class.call(user:, project:)
    expect(member_for(user, project)).to be_present

    assignment.destroy! # cascades the membership (dependent: :destroy)
    described_class.call(user:, project:)

    expect(member_for(user, project)).to be_nil
  end

  # --- 8: cascade cleanup when core removes the member --------------------
  it "drops managed bookkeeping when the underlying member is removed by core" do
    g = group_with_roles(role_a)
    add_to_group(g, user, project)
    described_class.call(user:, project:)
    expect(ProjectGroups::ManagedMemberRole.count).to eq(1)

    member_for(user, project).destroy! # e.g. user deleted / loses access via core

    expect(ProjectGroups::ManagedMemberRole.count).to eq(0)
  end

  # --- member events: drive storage (Nextcloud) folder-permission sync ------
  # We write Member/MemberRole directly, so we must emit the same events core's
  # group-inheritance emits, or the storages module never syncs folder access.
  describe "member events (storage permission sync)" do
    it "publishes MEMBER_CREATED without notifications when a member is materialised" do
      g = group_with_roles(role_a)
      add_to_group(g, user, project)

      expect(OpenProject::Notifications)
        .to receive(:send)
        .with(OpenProject::Events::MEMBER_CREATED, hash_including(send_notifications: false))
        .and_call_original

      described_class.call(user:, project:)
    end

    it "publishes MEMBER_DESTROYED when the user's last managed role is removed" do
      g = group_with_roles(role_a)
      membership = add_to_group(g, user, project)
      described_class.call(user:, project:)
      membership.destroy!

      expect(OpenProject::Notifications)
        .to receive(:send)
        .with(OpenProject::Events::MEMBER_DESTROYED, hash_including(send_notifications: false))
        .and_call_original

      described_class.call(user:, project:)
    end

    it "publishes nothing when already in sync (idempotent re-run)" do
      g = group_with_roles(role_a)
      add_to_group(g, user, project)
      described_class.call(user:, project:)

      expect(OpenProject::Notifications).not_to receive(:send)
      described_class.call(user:, project:)
    end
  end
end
